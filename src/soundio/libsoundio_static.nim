import os


const currentPath = splitFile(currentSourcePath()).dir
const soundioPath = joinPath(currentPath, "/libsoundio/")

when defined(Windows):
  const 
    defWASAPI     = true
    defJACK       = false
    defPULSEADIO  = false
    defALSA       = false
    defCOREADIO   = false
elif defined(Linux):
  const 
    defWASAPI     = false
    defJACK       = true
    defPULSEADIO  = true
    defALSA       = true
    defCOREADIO   = false
  {.
    passC: "-I/usr/include"
  .}
elif defined(MacOsX):
  const 
    defWASAPI     = false
    defJACK       = false
    defPULSEADIO  = false
    defALSA       = false
    defCOREADIO   = true
else:
  {.error: "this target platform is not supported".}

{. passC: "-I. -I" & soundioPath & " -I" & soundioPath & "soundio -I" & currentPath.}

# compile flags and files
when defWASAPI:
  {.
    passC: "-DSOUNDIO_HAVE_WASAPI=1",
    compile: soundioPath & "src/wasapi.c",
  .}
when defJACK:
  {.
    passC: "-DSOUNDIO_HAVE_JACK=1 -I" & currentPath & "deps/jack",
    compile: soundioPath & "src/jack.c",
    passL: "-ljack -lpthread",
  .}
when defPULSEADIO:
  {.  
    passC: "-DSOUNDIO_HAVE_PULSEAUDIO=1",
    compile: soundioPath & "src/pulseaudio.c",
    passL: "-D_REENTRANT -lpulse",
  .}
when defALSA:
  {.  
    passC: "-DSOUNDIO_HAVE_ALSA=1",
    compile: soundioPath & "src/alsa.c",
    passL: "-lasound",
  .}
when defCOREADIO:
  {.  
    passC: "-DSOUNDIO_HAVE_COREAUDIO=1",
    compile: soundioPath & "src/coreaudio.c",
  .}

{.
  compile: soundioPath & "src/soundio.c",
  compile: soundioPath & "src/util.c",
  compile: soundioPath & "src/os.c",
  compile: soundioPath & "src/dummy.c",
  compile: soundioPath & "src/channel_layout.c",
  compile: soundioPath & "src/ring_buffer.c",
.}