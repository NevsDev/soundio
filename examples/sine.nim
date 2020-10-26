import soundio, math

var PI*: cfloat = 3.1415926535

var seconds_offset*: cfloat = 0.0

proc write_callback*(outstream: ptr SoundIoOutStream, frame_count_min: cint, frame_count_max: cint) {.cdecl.} =
  var 
    layout: ptr SoundIoChannelLayout = addr(outstream.layout)
    float_sample_rate: cfloat = outstream.sample_rate.cfloat
    seconds_per_frame: cfloat = 1.0 / float_sample_rate
    areas: ptr UncheckedArray[SoundIoChannelArea]
    frames_left: cint = frame_count_max
    err: cint

  while frames_left > 0:
    var 
      frame_count: cint = frames_left
    err = soundio_outstream_begin_write(outstream, addr(areas), addr(frame_count))
    if err != 0:
      echo("Error 1", soundio_strerror(err))
      quit(1)
    if frame_count == 0:
      break
    var 
      pitch: cfloat = 440.0
      radians_per_second: cfloat = pitch * 2.0 * PI
    for frame in 0..<frame_count:
      var sample: cfloat = sin((seconds_offset + frame.cfloat * seconds_per_frame) * radians_per_second)
      for channel in 0..<layout.channel_count:
        write_sample(areas[channel], sample)
        areas[channel].data += areas[channel].step
    seconds_offset = (seconds_offset + seconds_per_frame * frame_count.cfloat) mod 1.0
    err = soundio_outstream_end_write(outstream)
    if err != 0:
      echo("Error 2", soundio_strerror(err))
      quit(1)
    dec(frames_left, frame_count)
  echo("end of write callback")

proc main*() =
  var err: cint
  var soundio: ptr SoundIo = soundio_create()
  if soundio == nil:
    echo("out of memory")
    quit(1)
  # err = soundio_connect_backend(soundio, SoundIoBackendAlsa)
  # err = soundio_connect_backend(soundio, SoundIoBackend)
  err = soundio_connect(soundio)
  if err != 0:
    echo("error connecting: ", soundio_strerror(err))
    quit(1)
  soundio_flush_events(soundio)
  var default_out_device_index: cint = soundio_default_output_device_index(soundio)
  if default_out_device_index < 0:
    echo("no output device found")
    quit 1
  var device: ptr SoundIoDevice = soundio_get_output_device(soundio, default_out_device_index)
  if device == nil:
    echo("out of memory")
    quit 1
  echo("Output device: ", device.name)
  var outstream: ptr SoundIoOutStream = soundio_outstream_create(device)
  if outstream == nil:
    echo("out of memory")
    quit 1

  outstream.format = SoundIoFormatFloat32NE
  # outstream.layout = soundio_channel_layout_get_default(2)[]
  outstream.write_callback = write_callback

  err = soundio_outstream_open(outstream)
  if err != 0:
    echo("unable to open device: ", soundio_strerror(err))
    quit 1
  if outstream.layout_error != 0:
    echo("unable to set channel layout: ", soundio_strerror(outstream.layout_error))
  err = soundio_outstream_start(outstream)
  if err != 0:
    echo("unable to start device: ", soundio_strerror(err))
    quit 1
  while true:
    soundio_wait_events(soundio)
  soundio_outstream_destroy(outstream)
  soundio_device_unref(device)
  soundio_destroy(soundio)
  quit(0)

main()