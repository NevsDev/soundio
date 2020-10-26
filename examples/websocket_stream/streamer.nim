# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
import strformat, soundio, os
import ws, asyncdispatch, asynchttpserver, json
import locks, threadpool

type 
  Buffer = ptr BufferObj

  BufferObj = object
    data: ptr UncheckedArray[float32]
    size: int
    max_size: int
    packet_id: uint32
    lock: Lock 

proc createBuffer(): Buffer =
  result = createShared(BufferObj)
  result.lock.initLock()

proc update*(buf: Buffer, data: ptr uint8, data_size: int) =
  withLock buf.lock:
    var new_size = data_size * 4
    if buf.max_size < new_size:
      buf.max_size = data_size
      buf.data = cast[ptr UncheckedArray[float32]](reallocShared(buf.data, new_size))
    buf.size = new_size
    # convert to float
    for i in 0..<data_size:
      buf.data[i] = data[i].float32 / 128.0 - 1.0
    # copyMem(buf.data[0].addr, data, data_size)
    buf.packet_id.inc()

proc sendTo*(buf: Buffer, ws: Websocket, last_packet: ptr uint32) {.async.} =
  var msg: string
  withLock buf.lock:
    if last_packet[] == buf.packet_id or buf.size == 0: 
      return
    msg.setLen(buf.size)
    copyMem(msg[0].addr, buf.data[0].addr, buf.size)

  last_packet[] = buf.packet_id
  await ws.send(msg, Opcode.Binary)

var abuffer: Buffer = createBuffer()

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Websocket Server 


    # SoundIoFormatU8,
    # SoundIoFormatS8,
    # SoundIoFormatU16NE,
    # SoundIoFormatS16NE,
    # SoundIoFormatU32NE,
    # SoundIoFormatS32NE,
    # SoundIoFormatFloat32NE,

    # 8000,
    # 24000,
    # 48000,
    # 44100,
    # 96000
const
  enc_format = SoundIoFormatU8
  channels = 1
  sampleRate = 8000
  flushingTime = 1000

var server = newAsyncHttpServer()
proc cb(req: Request) {.async.} =
  if req.url.path == "/ws":
    var ws = await newWebSocket(req)

    # 1. create player
    var msg = %*{
      "encoding": "32bitFloat",
      "channels": channels,
      "sampleRate": sampleRate,
      "flushingTime": flushingTime,
    }
    await ws.send($msg, Opcode.Text)

    # 2. send pcm stream
    var packetId = 0'u32
    while ws.readyState == Open:
      await sleepAsync(10)
      await abuffer.sendTo(ws, packetId.addr)
  else:
    await req.respond(Http404, "Not found")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

type RecordContext = object
  ring_buffer: ptr SoundIoRingBuffer

var 
  prioritized_formats = [enc_format]

  prioritized_sample_rates = [sampleRate]


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

proc record() =
  var
    backend = SoundIoBackendNone
    device_id: string
    is_raw = false
    rc: RecordContext
    soi: ptr SoundIo = soundio_create()
  if soi == nil:
    stdout.write("out of memory\n")
    quit(1)

  var err = if backend == SoundIoBackendNone: soundio_connect(soi) else: soundio_connect_backend(soi, backend)
  if err != 0:
    stdout.write("error connecting: " & $soundio_strerror(err))
    quit(1)

  soundio_flush_events(soi)
  var selected_device: ptr SoundIoDevice

  if device_id.len != 0:
    for i in 0..<soundio_input_device_count(soi):
      var device: ptr SoundIoDevice = soundio_get_input_device(soi, i)
      if device.is_raw == is_raw and device.id == device_id:
          selected_device = device
          break
      soundio_device_unref(device)
    if selected_device == nil:
      stdout.write(&"Invalid device id: {device_id}\n")
      quit(1)
  else:
    var device_index = soundio_default_input_device_index(soi)
    selected_device = soundio_get_input_device(soi, device_index)
    if selected_device == nil:
      stdout.write("No input devices available.\n")
      quit(1)

  stdout.write(&"Device: {selected_device.name}\n")

  if selected_device.probe_error != 0:
    stdout.write(&"Unable to probe device: {soundio_strerror(selected_device.probe_error)}\n")
    quit(1)

  soundio_device_sort_channel_layouts(selected_device)

  var sample_rate = 0
  for sample_rate_ptr in prioritized_sample_rates:
    if soundio_device_supports_sample_rate(selected_device, sample_rate_ptr.cint):
      sample_rate = sample_rate_ptr
      break

  if sample_rate == 0:
    sample_rate = selected_device.sample_rates[0].max

  var 
    fmt: SoundIoFormat = SoundIoFormatInvalid
  for fmt_ptr in prioritized_formats:
    if soundio_device_supports_format(selected_device, fmt_ptr):
      fmt = fmt_ptr
      break

  if fmt == SoundIoFormatInvalid:
    fmt = selected_device.formats[0]

  var instream: ptr SoundIoInStream = soundio_instream_create(selected_device)

  if instream == nil:
    stdout.write("out of memory\n")
    quit(1)

  var layout = soundio_channel_layout_get_default(channels) # get default channel layout for Mono
  if layout == nil:
    stdout.write("cound not select layout\n")
    quit(1)
    

  instream.format = fmt
  instream.sample_rate = sample_rate.cint
  instream.layout = layout[]

  instream.read_callback = read_callback
  instream.overflow_callback = overflow_callback
  instream.error_callback = error_callback
  instream.userdata = rc.addr

  echo "start record micro ", fmt, " ", sample_rate

  err = soundio_instream_open(instream)
  if err != 0:
    stdout.write("unable to open input stream: " & $soundio_strerror(err))
    quit(1)

  stdout.write(&"{instream.layout.name} {sample_rate}Hz {soundio_format_string(fmt)} interleaved\n")

  var 
    ring_buffer_duration_seconds: cint = 30
    capacity = ring_buffer_duration_seconds * instream.sample_rate * instream.bytes_per_frame

  rc.ring_buffer = soundio_ring_buffer_create(soi, capacity)
  if rc.ring_buffer == nil:
    stdout.write("out of memory\n")
    quit(1)

  err = soundio_instream_start(instream)
  if err != 0:
    stdout.write("unable to start input device: " & $soundio_strerror(err))
    quit(1)

  # Note: in this example, if you send SIGINT (by pressing Ctrl+C for example)
  # you will lose up to 1 second of recorded audio data. In non-example code,
  # consider a better shutdown strategy.
  while true:
    soundio_flush_events(soi)
    # sleep(flushingTime)
    var 
      fill_bytes = soundio_ring_buffer_fill_count(rc.ring_buffer)
    
    if fill_bytes > 0:
      var
        read_buf = soundio_ring_buffer_read_ptr(rc.ring_buffer)

      abuffer.update(read_buf, fill_bytes)
      soundio_ring_buffer_advance_read_ptr(rc.ring_buffer, fill_bytes)
  echo "out "

  soundio_instream_destroy(instream)
  soundio_device_unref(selected_device)
  soundio_destroy(soi)


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

spawn record()
waitFor server.serve(Port(9001), cb)
