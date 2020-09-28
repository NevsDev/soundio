# Package

version       = "0.1.0"
author        = "Sven Keller"
description   = "bindings to libsoundio - auto binding"
license       = "MIT"
srcDir        = "src"



# Dependencies
before install:
  exec("git clone https://github.com/andrewrk/libsoundio")

requires "nim >= 1.0.0"
