# Package

version       = "0.1.0"
author        = "Takeyoshi Kikuchi"
description   = "Nim Asynchronous Modbus library."
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
installExt    = @["nim"]
bin           = @["nim_asyncmodbus"]


# Dependencies

requires "nim >= 1.6.8"
requires "serial >= 1.1.5"
