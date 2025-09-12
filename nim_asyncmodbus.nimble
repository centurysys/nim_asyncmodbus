# Package

version       = "0.3.0"
author        = "Takeyoshi Kikuchi"
description   = "Nim Asynchronous Modbus library."
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
installExt    = @["nim"]
bin           = @["nim_asyncmodbus"]


# Dependencies

requires "nim >= 2.2.4"
requires "serial >= 1.2.0"
