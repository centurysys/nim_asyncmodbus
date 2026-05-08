import ../core
import ../util

# ------------------------------------------------------------------------------
# TCP Frame builder:
# ------------------------------------------------------------------------------
proc buildTcpQueryFrame*(transactionId: uint16, target: uint8, cmd: FunctionCode,
    regAddr: uint16, nb: uint16): seq[uint8] =
  let address = normalizeRegAddr(regAddr)
  const
    dataLen = 2 + 4
    payloadLen = 6 + dataLen

  result = newSeq[uint8](payloadLen)
  result.setBe16(0, transactionId)
  result.setBe16(2, 0)
  result.setBe16(4, dataLen)
  result[6] = target
  result[7] = cmd.uint8
  result.setBe16(8, address - 1)
  result.setBe16(10, nb)

# ------------------------------------------------------------------------------
# TCP Frame builder:
# ------------------------------------------------------------------------------
proc buildTcpWriteFrame*(transactionId: uint16, target: uint8, cmd: FunctionCode,
    regAddr: uint16, data: openArray[uint8]): seq[uint8] =
  let
    address = normalizeRegAddr(regAddr)
    dataLen = 2 + 2 + data.len
    payloadLen = 6 + dataLen

  result = newSeq[uint8](payloadLen)
  result.setBe16(0, transactionId)
  result.setBe16(2, 0)
  result.setBe16(4, dataLen.uint16)
  result[6] = target
  result[7] = cmd.uint8
  result.setBe16(8, address - 1)
  for idx in 0 ..< data.len:
    result[10 + idx] = data[idx]
