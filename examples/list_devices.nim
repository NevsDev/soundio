import strformat, soundio

var 
  backend: SoundIoBackend = SoundIoBackendAlsa
  watch: bool = true
  short_output = false
  sio: ptr SoundIo = soundio_create()


proc printChannelLayout(layout: SoundIoChannelLayout) =
  if layout.name != nil:
    stdout.write($layout.name)
  else:
    stdout.write(soundio_get_channel_name(layout.channels[0]))
    for j in 1..<layout.channel_count:
      stdout.write(", " & $soundio_get_channel_name(layout.channels[j]))

proc printDevice*(device: ptr SoundIoDevice, default: bool) =
  var
    default_str = if default: " (default)" else: "" 
    raw_str = if device.is_raw: " (raw)" else: ""
  stdout.write(&"{device.name}{default_str}{raw_str}\n  id: {device.id}\n")
  if short_output: return

  if device.probe_error != 0: 
    stdout.write(" probe error: " & $soundio_strerror(device.probe_error) & "\n")
  else:
    stdout.write("  channel layouts:\n")
    for i in 0..<device.layout_count:
      stdout.write("      ")
      printChannelLayout(device.layouts[i])
      stdout.write("\n")
    
    if device.current_layout.channel_count > 0:
      stdout.write("  current layout: ")
      printChannelLayout(device.current_layout)
      stdout.write("\n")

    stdout.write("  sample rates:\n")
    for i in 0..<device.sample_rate_count:
      var samp_range = device.sample_rates[i]
      stdout.write(&"    {samp_range.min} - {samp_range.max}\n")

    if device.sample_rate_current != 0:
      stdout.write(&"  current sample rate: {device.sample_rate_current}\n")
    stdout.write("  formats: ")
    for i in 0..<device.format_count:
      var comma = if i == device.format_count - 1: "" else: ", "
      stdout.write(soundio_format_string(device.formats[i]), comma)

    stdout.write("\n")
    if device.current_format != SoundIoFormatInvalid:
      stdout.write(&"  current format: {soundio_format_string(device.current_format)}\n")

    stdout.write(&"  min software latency: {device.software_latency_min:.8f} sec\n")
    stdout.write(&"  max software latency: {device.software_latency_max:.8f} sec\n")
    if device.software_latency_current != 0.0:
      stdout.write(&"  current software latency: {device.software_latency_current:.8f} sec\n")


proc listDevices(sio: ptr SoundIo) = 
  var 
    output_count = soundio_output_device_count(sio)
    input_count = soundio_input_device_count(sio)

    default_output = soundio_default_output_device_index(sio)
    default_input = soundio_default_input_device_index(sio)

  stdout.write("--------Input Devices--------\n\n")
  for i in 0..<input_count:
    var device: ptr SoundIoDevice = soundio_get_input_device(sio, i)
    printDevice(device, default_input == i)
    soundio_device_unref(device)
  stdout.write("\n--------Output Devices--------\n\n")
  for i in 0..<output_count:
    var device: ptr SoundIoDevice = soundio_get_output_device(sio, i)
    printDevice(device, default_output == i)
    soundio_device_unref(device)

  stdout.write(&"\n{input_count + output_count} devices found\n")

proc onDevicesChange(sio: ptr SoundIo) {.stdcall, cdecl.} =
    stdout.write("devices changed\n")
    listDevices(sio)

proc main() =
  if sio == nil:
    echo "out of memory\n"
    quit(1)

  var err = if backend == SoundIoBackendNone: soundio_connect(sio) 
            else: soundio_connect_backend(sio, backend)

  if err != 0:
    echo soundio_strerror(err)
    quit(err)

  if watch:
    sio.on_devices_change = onDevicesChange
    while true:
      soundio_wait_events(sio)
  else:
    soundio_flush_events(sio)
    sio.listDevices()
    soundio_destroy(sio)

main()