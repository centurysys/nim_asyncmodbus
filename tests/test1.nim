import unittest

import nim_asyncmodbuspkg/private/crc16
test "Modbus CRC-16":
  const buf = [0x01'u8, 0x04, 0x00, 0x00, 0x00, 0x01]
  let crc = calcCrcModbus(buf)
  check crc == 0xca31
