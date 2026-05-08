import ../core
import ../util
import ./crc16

# ------------------------------------------------------------------------------
# RTU Frame builder:
# ------------------------------------------------------------------------------
proc setCrc(buf: openArray[uint8], pos: uint) =
  let crc = calcCrcModbus(buf[0 ..< pos])
  buf.setLe16(pos, crc)

# ------------------------------------------------------------------------------
# RTU Frame builder:
# ------------------------------------------------------------------------------
proc buildRtuQueryFrame*(slaveAddr: uint8, cmd: FunctionCode,
    regAddr: uint16, nb: uint16): seq[uint8] =
  let address = normalizeRegAddr(regAddr)

  result = newSeq[uint8](8)
  result[0] = slaveAddr
  result[1] = cmd.uint8
  result.setBe16(2, address - 1)
  result.setBe16(4, nb)
  result.setCrc(6)

# ------------------------------------------------------------------------------
# RTU Frame builder:
# ------------------------------------------------------------------------------
proc buildRtuWriteFrame*(slaveAddr: uint8, cmd: FunctionCode,
    regAddr: uint16, data: openArray[uint8]): seq[uint8] =
  let
    address = normalizeRegAddr(regAddr)
    payloadLen = 4 + data.len + 2

  result = newSeq[uint8](payloadLen)
  result[0] = slaveAddr
  result[1] = cmd.uint8
  result.setBe16(2, address - 1)
  for idx in 0 ..< data.len:
    result[4 + idx] = data[idx]
  result.setCrc((payloadLen - 2).uint)
