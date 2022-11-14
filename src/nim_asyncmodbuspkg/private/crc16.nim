proc createCrcTable(poly: uint16): array[0..255, uint16] =
  for i in 0..255:
    var crc = i.uint16
    for j in 0 ..< 8:
      let bit_one = (crc and 1) != 0
      crc = crc shr 1
      if bit_one:
        crc = crc xor poly
    result[i] = crc

const crcTable = createCrcTable(0xa001)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc calc_CRC_Modbus*(buf: openArray[char|uint8]): uint16 =
  result = uint16(0xffff)
  for ch in buf:
    let idx = (ch.uint8 xor (result and 0xff).uint8)
    result = (result shr 8) xor crcTable[idx]


when isMainModule:
  import strformat

  for i, val in crcTable.pairs:
    if (i mod 16) == 0:
      stdout.write(&"{i:02X}")
    stdout.write(&" {val:04x}")
    if (i mod 16) == 15:
      stdout.write("\n")

  block:
    let buf = [0x01'u8, 0x04, 0x00, 0x00, 0x00, 0x01]
    let crc = calc_CRC_Modbus(buf)
    echo &"0x{crc:04x}"
  block:
    let buf = [0x02'u8, 0x01, 0x00, 0x00, 0x00, 0x08]
    let crc = calc_CRC_Modbus(buf)
    echo &"0x{crc:04x}"
