# Package

version       = "0.1.0"
author        = "Takeyoshi Kikuchi"
description   = "Nim Modbus library."
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["nim_modbus"]


# Dependencies

requires "nim >= 1.6.8"
requires "serial >= 1.1.5"
