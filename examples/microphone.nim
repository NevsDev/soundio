import soundio, strformat, strutils, os, math

var 
  ring_buffer: ptr SoundIoRingBuffer 
  prioritized_formats = [
    SoundIoFormatFloat32NE,
    SoundIoFormatFloat32FE, 
    SoundIoFormatS32NE, 
    SoundIoFormatS32FE,
    SoundIoFormatS24NE, 
    SoundIoFormatS24FE, 
    SoundIoFormatS16NE, 
    SoundIoFormatS16FE,
    SoundIoFormatFloat64NE,
    SoundIoFormatFloat64FE,
    SoundIoFormatU32NE,
    SoundIoFormatU32FE,
    SoundIoFormatU24NE,
    SoundIoFormatU24FE,
    SoundIoFormatU16NE,
    SoundIoFormatU16FE,
    SoundIoFormatS8,
    SoundIoFormatU8
  ]
  prioritized_sample_rates = [48000.cint, 44100, 24000, 16000, 8000, 96000]


proc panic(msg: varargs[string, `$`]) =
  for i in 0..<msg.len:
    stdout.write msg[i] & " "
  stdout.write "\n"
  quit()

proc read_callback*(instream: ptr SoundIoInStream; frame_count_min: cint; frame_count_max: cint) {.cdecl.} =
  var 
    areas: ptr UncheckedArray[SoundIoChannelArea]
    err: cint
    write_ptr = soundio_ring_buffer_write_ptr(ring_buffer)
    free_bytes = soundio_ring_buffer_free_count(ring_buffer)
    free_count = free_bytes div instream.bytes_per_frame

  if frame_count_min > free_count:
    panic("ring buffer overflow")

  var
    write_frames: cint = min(free_count, frame_count_max)
    frames_left = write_frames

  while true:
    var frame_count = frames_left
    err = soundio_instream_begin_read(instream, addr(areas), addr(frame_count))
    if err != 0:
      panic("begin read error: ", err,  soundio_strerror(err))
    if frame_count == 0:
      break
    if areas == nil:
      ##  Due to an overflow there is a hole. Fill the ring buffer with
      ##  silence for the size of the hole.
      for i in 0..<frame_count * instream.bytes_per_frame:
        write_ptr[0] = 0
      echo("Dropped %d frames due to internal overflow")
    else:
      for frame in 0..<frame_count:
        for ch in 0..<instream.layout.channel_count:
          copyMem(write_ptr, areas[ch].data, instream.bytes_per_sample)
          areas[ch].data += areas[ch].step
          write_ptr += instream.bytes_per_sample

    err = soundio_instream_end_read(instream)
    if err != 0:
      panic("end read error: ", soundio_strerror(err))

    dec(frames_left, frame_count)
    if frames_left <= 0:
      break
  var advance_bytes: cint = write_frames * instream.bytes_per_frame
  soundio_ring_buffer_advance_write_ptr(ring_buffer, advance_bytes)


proc write_callback*(outstream: ptr SoundIoOutStream; frame_count_min: cint; frame_count_max: cint) {.cdecl.} =
  var 
    areas: ptr UncheckedArray[SoundIoChannelArea]
    frames_left, frame_count, err: cint
    read_ptr = soundio_ring_buffer_read_ptr(ring_buffer)
    fill_bytes: cint = soundio_ring_buffer_fill_count(ring_buffer)
    fill_count: cint = fill_bytes div outstream.bytes_per_frame

  if frame_count_min > fill_count:
    ##  Ring buffer does not have enough data, fill with zeroes.
    frames_left = frame_count_min
    while true:
      frame_count = frames_left
      if frame_count <= 0:
        return
      err = soundio_outstream_begin_write(outstream, addr(areas), addr(frame_count))
      if err == 0:
        panic("begin write error: ", soundio_strerror(err))
      if frame_count <= 0:
        return

      for frame in 0..<frame_count:
        for ch in 0..<outstream.layout.channel_count:
          for i in 0..<outstream.bytes_per_frame:
            areas[ch].data[i] = 0
          areas[ch].data += areas[ch].step

      err = soundio_outstream_end_write(outstream)
      if err == 0:
        panic("end write error: ", soundio_strerror(err))
      dec(frames_left, frame_count)

  var read_count: cint = min(frame_count_max, fill_count)
  frames_left = read_count

  while frames_left > 0:
    var frame_count: cint = frames_left
    err = soundio_outstream_begin_write(outstream, addr(areas), addr(frame_count))
    if err != 0:
      panic("begin write error: ", soundio_strerror(err))
    if frame_count <= 0:
      break
    for frame in 0..<frame_count:
      for ch in 0..<outstream.layout.channel_count:
        copyMem(areas[ch].data, read_ptr, outstream.bytes_per_sample)
        areas[ch].data += areas[ch].step
        read_ptr += outstream.bytes_per_sample

    err = soundio_outstream_end_write(outstream)
    if err != 0:
      panic("end write error: ", soundio_strerror(err))

    dec(frames_left, frame_count)
  soundio_ring_buffer_advance_read_ptr(ring_buffer, read_count * outstream.bytes_per_frame)

proc underflow_callback*(outstream: ptr SoundIoOutStream) {.cdecl.} =
  echo("underflow")

proc usage*(exe: string): int =
  echo &"""
Usage: {exe} [options]
Options:
  [--backend dummy|alsa|pulseaudio|jack|coreaudio|wasapi]
  [--in-device id]
  [--in-raw]
  [--out-device id]
  [--out-raw]
  [--latency seconds]
"""
  return 1

proc main(): int =
  var
    exe = paramStr(0)
    argc = paramCount()
    backend: SoundIoBackend = SoundIoBackendNone

    in_device_id, out_device_id: string
    in_raw, out_raw: bool
    microphone_latency: cdouble = 0.1
    
  ##  seconds
  for i in 1..<argc:
    var arg = paramStr(i)
    if arg[0..1] == "--":
      var i_next = i + 1
      if arg == "--in-raw":
        in_raw = true
      elif arg == "--out-raw":
        out_raw = true
      elif i_next >= argc:
        return usage(exe)
      elif arg == "--backend":
        case paramStr(i_next):
        of "dummy":
          backend = SoundIoBackendDummy
        of "alsa":
          backend = SoundIoBackendAlsa
        of "pulseaudio":
          backend = SoundIoBackendPulseAudio
        of "jack":
          backend = SoundIoBackendJack
        of "coreaudio":
          backend = SoundIoBackendCoreAudio
        of "wasapi":
          backend = SoundIoBackendWasapi
        else:
          stdout.write(&"Invalid backend: {paramStr(i_next)}\n")
          return 1
      elif arg == "--in-device":
        in_device_id = paramStr(i_next)
      elif arg == "--out-device":
        out_device_id = paramStr(i_next)
      elif arg == "--latency":
        microphone_latency = parseFloat(paramStr(i_next))
      else:
        return usage(exe)
    else:
      return usage(exe)

  var soundio: ptr SoundIo = soundio_create()
  if soundio == nil:
    panic("out of memory")
  var err = if (backend == SoundIoBackendNone): soundio_connect(soundio) else: soundio_connect_backend(soundio, backend)
  if err != 0:
    panic("error connecting: ", soundio_strerror(err))

  soundio_flush_events(soundio)
  var default_out_device_index = soundio_default_output_device_index(soundio)
  if default_out_device_index < 0:
    panic("no output device found")
  var default_in_device_index = soundio_default_input_device_index(soundio)
  if default_in_device_index < 0:
    panic("no input device found")
  var in_device_index = default_in_device_index
  if in_device_id.len != 0:
    var found: bool = false
    for i in 0..<soundio_input_device_count(soundio):
      var device: ptr SoundIoDevice = soundio_get_input_device(soundio, i)
      if device.is_raw == in_raw and $device.id == in_device_id:
        in_device_index = i
        found = true
        soundio_device_unref(device)
        break
      soundio_device_unref(device)
    if not found:
      panic("invalid input device id: ", in_device_id)

  var out_device_index: cint = default_out_device_index
  if out_device_id.len != 0:
    var found: bool = false
    for i in 0..<soundio_output_device_count(soundio):
      var device: ptr SoundIoDevice = soundio_get_output_device(soundio, i)
      if device.is_raw == out_raw and $device.id == out_device_id:
        out_device_index = i
        found = true
        soundio_device_unref(device)
        break
      soundio_device_unref(device)
    if not found:
      panic("invalid output device id: ", out_device_id)

  var out_device: ptr SoundIoDevice = soundio_get_output_device(soundio, out_device_index)
  if out_device == nil:
    panic("could not get output device: out of memory")
  var in_device: ptr SoundIoDevice = soundio_get_input_device(soundio, in_device_index)
  if in_device == nil:
    panic("could not get input device: out of memory")

  echo("Input device: ", in_device.name)
  echo("Output device: ", out_device.name)
  
  soundio_device_sort_channel_layouts(out_device)
  var layout = soundio_best_matching_channel_layout(
      out_device.layouts, out_device.layout_count, 
      in_device.layouts, in_device.layout_count)
  if layout == nil:
    panic("channel layouts not compatible")

  var sample_rate: cint = 0
  for test_sample_rate in prioritized_sample_rates:
    if soundio_device_supports_sample_rate(in_device, test_sample_rate) and soundio_device_supports_sample_rate(out_device, test_sample_rate):
      sample_rate = test_sample_rate
      break
  
  if sample_rate == 0:
    panic("incompatible sample rates")

  var fmt: SoundIoFormat = SoundIoFormatInvalid
  for test_fmt in prioritized_formats:
    if soundio_device_supports_format(in_device, test_fmt) and soundio_device_supports_format(out_device, test_fmt):
      fmt = test_fmt
      break
  if fmt == SoundIoFormatInvalid:
    panic("incompatible sample formats")

  var instream: ptr SoundIoInStream = soundio_instream_create(in_device)
  if instream == nil:
    panic("out of memory")
  instream.format = fmt
  instream.sample_rate = sample_rate
  instream.layout = layout[]
  instream.software_latency = microphone_latency
  instream.read_callback = read_callback

  err = soundio_instream_open(instream)
  if err != 0:
    echo("unable to open input stream: ", soundio_strerror(err))
    return 1

  var outstream: ptr SoundIoOutStream = soundio_outstream_create(out_device)
  if outstream == nil:
    panic("out of memory")
  outstream.format = fmt
  outstream.sample_rate = sample_rate
  outstream.layout = layout[]
  outstream.software_latency = microphone_latency
  outstream.write_callback = write_callback
  outstream.underflow_callback = underflow_callback

  err = soundio_outstream_open(outstream)
  if err != 0:
    echo("unable to open output stream: ", soundio_strerror(err))
    return 1

  var capacity: cint = ceil(microphone_latency * 2.0 * instream.sample_rate.cdouble * instream.bytes_per_frame.cdouble).cint
  ring_buffer = soundio_ring_buffer_create(soundio, capacity)
  if ring_buffer == nil:
    panic("unable to create ring buffer: out of memory")

  var buf = soundio_ring_buffer_write_ptr(ring_buffer)
  var fill_count: cint = ceil(microphone_latency * outstream.sample_rate.cdouble * outstream.bytes_per_frame.cdouble).cint
  for i in 0..<fill_count:
    buf[i] = 0

  soundio_ring_buffer_advance_write_ptr(ring_buffer, fill_count)
  err = soundio_instream_start(instream)
  if err != 0:
    panic("unable to start input device: ", soundio_strerror(err))
  err = soundio_outstream_start(outstream)
  if err != 0:
    panic("unable to start output device: %s", soundio_strerror(err))

  while true:
    soundio_wait_events(soundio)
  soundio_outstream_destroy(outstream)
  soundio_instream_destroy(instream)
  soundio_device_unref(in_device)
  soundio_device_unref(out_device)
  soundio_destroy(soundio)
  return 0

quit main()