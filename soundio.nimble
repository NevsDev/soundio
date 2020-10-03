# Package

version       = "0.1.0"
author        = "Sven Keller"
description   = "bindings to libsoundio - auto binding"
license       = "MIT"
srcDir        = "src"



requires "nim >= 1.0.0"


import distros
proc installDeps() = 
  if detectOs(Ubuntu):
    # "pkg-config --cflags --libs jack"
    # sudo apt-get install -y libpulse-dev
    exec "sudo apt-get install -y libjack-dev"
    exec "sudo apt-get install -y libpulse-dev"

  # sudo apt-get install -y libjack-dev
  # sudo apt-get install -y libaudio-dev
  # sudo apt-get install -y libpulse-dev
  # sudo apt-get install -y libasound2-dev   


before install:
  installDeps()