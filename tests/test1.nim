import unittest

import nim_modbuspkg/private/crc16
test "Modbus CRC-16":
  const buf = [0x01'u8, 0x04, 0x00, 0x00, 0x00, 0x01]
  let crc = calc_CRC_Modbus(buf)
  check crc == 0xca31
