import os


const currentPath = splitFile(currentSourcePath()).dir

{. passL: " " & currentPath & "/binaries/libsoundio.a -lasound -ljack -lpthread -D_REENTRANT -lpulse".}
