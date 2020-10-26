import strformat, soundio, os, cortona_sound/wave



type RecordContext = object
  ring_buffer: ptr SoundIoRingBuffer

var 
  prioritized_formats = [
    SoundIoFormatU32NE,
    SoundIoFormatU32FE,
    SoundIoFormatU24NE,
    SoundIoFormatU24FE,
    SoundIoFormatU16NE,
    SoundIoFormatU16FE,
    SoundIoFormatS8,
    SoundIoFormatU8,
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
    SoundIoFormatInvalid
  ]

  prioritized_sample_rates = [
    8000,
    16000,
    24000,
    44100,
    48000,
    96000,
    0,
  ]


proc error_callback(a1: ptr SoundIoInStream; err: cint) {.cdecl.} = 
  echo soundio_strerror(err)

proc read_callback(instream: ptr SoundIoInStream, frame_count_min, frame_count_max: cint) {.cdecl.} =
  var
    rc: ptr RecordContext = cast[ptr RecordContext](instream.userdata)
    areas: ptr UncheckedArray[SoundIoChannelArea]
    err: cint

    write_ptr = soundio_ring_buffer_write_ptr(rc.ring_buffer)
    free_bytes = soundio_ring_buffer_free_count(rc.ring_buffer)
    free_count = free_bytes div instream.bytes_per_frame

  if free_count < frame_count_min:
    stdout.write("ring buffer overflow\n")
    quit(1)

  # echo free_count, " ", frame_count_max
  var 
    write_frames = min(free_count, frame_count_max)
    frames_left = write_frames

  while true:
    var frame_count = frames_left
    err = soundio_instream_begin_read(instream, areas.addr, frame_count.addr)
    if err != 0:
      stdout.write("begin read error: " & $soundio_strerror(err))
      quit(1)

    if frame_count == 0:
      break

    if areas == nil:
      # Due to an overflow there is a hole. Fill the ring buffer with
      # silence for the size of the hole.
      for i in 0..<frame_count * instream.bytes_per_frame:
        write_ptr[0] = 0
    else:
      for frame in 0..<frame_count:
        for ch in 0..<instream.layout.channel_count:
          copyMem(write_ptr, areas[ch].data, instream.bytes_per_sample)
          areas[ch].data += areas[ch].step
          write_ptr += instream.bytes_per_sample

    err = soundio_instream_end_read(instream)
    if err != 0:
      stdout.write("end read error: " & $soundio_strerror(err))
      quit(1)

    frames_left -= frame_count
    if frames_left <= 0:
      break
  var advance_bytes = write_frames * instream.bytes_per_frame
  soundio_ring_buffer_advance_write_ptr(rc.ring_buffer, advance_bytes)

proc overflow_callback(instream: ptr SoundIoInStream) {.cdecl.} =
  var count = 0
  count.inc
  stdout.write(&"overflow {count}\n")

proc usage(exe: string): int =
  stdout.write(&"""Usage: {exe} [options] outfile.wav
Options:
  [--backend dummy|alsa|pulseaudio|jack|coreaudio|wasapi]
  [--device id]
  [--raw]
""")
  return 1

proc main(): int =
  var
    exe = paramStr(0)
    argc = paramCount()
    backend = SoundIoBackendNone
    device_id: string
    is_raw = false
    outfile: string
  for i in 1..<argc:
    var arg = paramStr(i)
    if arg[0..1] == "--":
      var i_next = i + 1
      if arg == "--raw":
        is_raw = true
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
      elif arg == "--device":
        device_id = paramStr(i)
      else:
        return usage(exe)
    elif outfile.len == 0:
      outfile = paramStr(i)
    else:
      return usage(exe)
  if outfile.len == 0:
    outfile = "testfile.wav"
    # return usage(exe)

  var 
    rc: RecordContext
    soi: ptr SoundIo = soundio_create()
  if soi == nil:
    stdout.write("out of memory\n")
    return 1

  var err = if backend == SoundIoBackendNone: soundio_connect(soi) else: soundio_connect_backend(soi, backend)
  if err != 0:
    stdout.write("error connecting: " & $soundio_strerror(err))
    return 1

  soundio_flush_events(soi)
  var selected_device: ptr SoundIoDevice

  var default_input_index = soundio_default_input_device_index(soi)
  selected_device = soundio_get_input_device(soi, default_input_index)
  if selected_device == nil:
    stdout.write(&"Invalid device. No default device\n")
    return 1
  echo selected_device[]
  stdout.write(&"Device: {selected_device.name}\n")


  # if device_id.len != 0:
  #   for i in 0..<soundio_input_device_count(soi):
  #     var device: ptr SoundIoDevice = soundio_get_input_device(soi, i)
  #     if device.is_raw == is_raw and device.id == device_id:
  #         selected_device = device
  #         break
  #     soundio_device_unref(device)
  #   if selected_device == nil:
  #     stdout.write(&"Invalid device id: {device_id}\n")
  #     return 1
  # else:
  #   var device_index = soundio_default_input_device_index(soi)
  #   selected_device = soundio_get_input_device(soi, device_index)
  #   if selected_device == nil:
  #     stdout.write("No input devices available.\n")
  #     return 1


  if selected_device.probe_error != 0:
    stdout.write(&"Unable to probe device: {soundio_strerror(selected_device.probe_error)}\n")
    return 1

  soundio_device_sort_channel_layouts(selected_device)

  # var 
  #   channel_layout_count = soundio_channel_layout_builtin_count()
  # for i in 0..<channel_layout_count:
  #   var layout = soundio_channel_layout_get_builtin(i)
  #   echo i, " LAYOUT: ", layout[]

  var layout = soundio_channel_layout_get_default(1) # get default channel layout for Mono

  var sample_rate = 0
  for sample_rate_ptr in prioritized_sample_rates:
    if soundio_device_supports_sample_rate(selected_device, sample_rate_ptr.cint):
      sample_rate = sample_rate_ptr
      break
  if sample_rate == 0:
    sample_rate = selected_device.sample_rates[0].max

  var fmt: SoundIoFormat = SoundIoFormatInvalid
  for fmt_ptr in prioritized_formats:
    if soundio_device_supports_format(selected_device, fmt_ptr):
      fmt = fmt_ptr
      break

  if fmt == SoundIoFormatInvalid:
    fmt = selected_device.formats[0]

  var 
    out_f = WaveFile.open(outfile, fmWrite)
    instream: ptr SoundIoInStream = soundio_instream_create(selected_device)

  if instream == nil:
    stdout.write("out of memory\n")
    return 1
  
  var 
    bytes_per_sample = soundio_get_bytes_per_sample(fmt)

  instream.format = fmt
  instream.sample_rate = sample_rate.cint
  instream.layout = layout[]
  
  instream.read_callback = read_callback
  instream.overflow_callback = overflow_callback
  instream.error_callback = error_callback
  instream.userdata = rc.addr

  out_f.format = PCM
  out_f.channels = layout.channel_count
  out_f.sample_rate = sample_rate
  out_f.sample_size = bytes_per_sample
  out_f.write_header()

  err = soundio_instream_open(instream)
  if err != 0:
    stdout.write("unable to open input stream: " & $soundio_strerror(err))
    return 1


  stdout.write(&"{instream.layout.name} {sample_rate}Hz {soundio_format_string(fmt)} interleaved\n")

  var 
    ring_buffer_duration_seconds: cint = 30
    capacity = ring_buffer_duration_seconds * instream.sample_rate * instream.bytes_per_frame

  rc.ring_buffer = soundio_ring_buffer_create(soi, capacity)
  if rc.ring_buffer == nil:
    stdout.write("out of memory\n")
    return 1

  err = soundio_instream_start(instream)
  if err != 0:
    stdout.write("unable to start input device: " & $soundio_strerror(err))
    return 1

  # Note: in this example, if you send SIGINT (by pressing Ctrl+C for example)
  # you will lose up to 1 second of recorded audio data. In non-example code,
  # consider a better shutdown strategy.
  var  count = 0
  while count < 10:
    soundio_flush_events(soi)
    sleep(1000)
    var 
      fill_bytes = soundio_ring_buffer_fill_count(rc.ring_buffer)
      read_buf = soundio_ring_buffer_read_ptr(rc.ring_buffer)
    
    if fill_bytes > 0:
      var
        amt = out_f.writeSamples(read_buf, fill_bytes)
      echo "read ringbuffer ", fill_bytes
      # if amt != fill_bytes:
      #   stdout.write(&"write error\n")
      #   return 1
      soundio_ring_buffer_advance_read_ptr(rc.ring_buffer, fill_bytes)
      count.inc
  out_f.flush()
  out_f.close()
  echo "out "

  soundio_instream_destroy(instream)
  soundio_device_unref(selected_device)
  soundio_destroy(soi)
  return 0

discard main()