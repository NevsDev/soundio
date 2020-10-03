import soundio

var 
  backend: SoundIoBackend = Alsa
  watch: bool = false
  sio: ptr SoundIo = soundio_create()


# proc list_devices(struct SoundIo *soundio):  int = 
#   int output_count = soundio_output_device_count(soundio)
#   int input_count = soundio_input_device_count(soundio);

#   int default_output = soundio_default_output_device_index(soundio);
#   int default_input = soundio_default_input_device_index(soundio);

#   fprintf(stderr, "--------Input Devices--------\n\n");
#   for (int i = 0; i < input_count; i += 1) {
#       struct SoundIoDevice *device = soundio_get_input_device(soundio, i);
#       print_device(device, default_input == i);
#       soundio_device_unref(device);
#   }
#   fprintf(stderr, "\n--------Output Devices--------\n\n");
#   for (int i = 0; i < output_count; i += 1) {
#       struct SoundIoDevice *device = soundio_get_output_device(soundio, i);
#       print_device(device, default_output == i);
#       soundio_device_unref(device);
#   }

#   fprintf(stderr, "\n%d devices found\n", input_count + output_count);
#   return 0

proc main() =
  if sio == nil:
    echo "out of memory\n"
    quit(1)

  var err = if backend == SoundIoBackend.None: connect(sio) 
            else: connect(sio, backend)

  if err != 0:
    echo strerror(err)
    quit(err)

  # if watch:
  #   sio.on_devices_change = on_devices_change
  #   while true
  #     soundio_wait_events(sio)
  # else:
  #   soundio_flush_events(sio)
  #   var err = list_devices(sio)
  #   soundio_destroy(sio)
  #   quit(err)


main()