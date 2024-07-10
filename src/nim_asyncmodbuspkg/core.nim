import std/asyncdispatch
import std/options

type
  ModbusCtxObj* = object of RootObj
  ModbusCtx* = ref ModbusCtxObj
  FunctionCode* = enum
    fcReadCoilStatus = 0x01
    fcReadInputStatus = 0x02
    fcReadHoldingRegister = 0x03
    fcReadInputRegister = 0x04
    fcForceSingleCoil = 0x05
    fcPresetSingleRegister = 0x06
    fcDiagnostics = 0x08
    fcFetchCommEventCounter = 0x0b
    fcFetchCommEventLog = 0x0c
    fcForceMultipleCoils = 0x0f
    fcPresetMultipleRegisters = 0x10
    fcReportSlaveId = 0x11
  DiagCode* = enum
    dcReturnQueryData = 0x00
  ErrorCode* = enum
    errInvalidFunction = 1
    errInvalidAddress = 2
    errInvalidData = 3
    errServerFailure = 4
    errAcknowledge = 5
    errServerBusy = 6
    errGatewayProblem0A = 0x0a
    errGatewayProblem0B = 0x0b
  CoilStatus* = enum
    CoilOff = 0x0000
    CoilOn = 0xff00


method connect*(self: ModbusCtx, timeout: uint): Future[bool] {.base, async.} =
  discard

method close*(self: ModbusCtx) {.base.} =
  discard

method readBits*(self: ModbusCtx, target: uint8, regAddr: uint16,
    nb: uint16): Future[seq[bool]] {.base, async.} =
  discard

method readBits*(self: ModbusCtx, regAddr: uint16, nb: uint16):
    Future[seq[bool]] {.base, async.} =
  discard

method readInputBits*(self: ModbusCtx, target: uint8, regAddr: uint16,
    nb: uint16): Future[seq[bool]] {.base, async.} =
  discard

method readInputBits*(self: ModbusCtx, regAddr: uint16, nb: uint16):
    Future[seq[bool]] {.base, async.} =
  discard

method readRegisters*(self: ModbusCtx, target: uint8, regAddr: uint16,
    nb: uint16): Future[seq[uint16]] {.base, async.} =
  discard

method readRegisters*(self: ModbusCtx, regAddr: uint16, nb: uint16):
    Future[seq[uint16]] {.base, async.} =
  discard

method readInputRegisters*(self: ModbusCtx, target: uint8, regAddr: uint16,
    nb: uint16): Future[seq[uint16]] {.base, async.} =
  discard

method readInputRegisters*(self: ModbusCtx, regAddr: uint16, nb: uint16):
    Future[seq[uint16]] {.base, async.} =
  discard

method writeBit*(self: ModbusCtx, target: uint8, regAddr: uint16, onoff: bool):
    Future[bool] {.base, async.} =
  discard

method writeBit*(self: ModbusCtx, regAddr: uint16, onoff: bool): Future[bool]
    {.base, async.} =
  discard

func normalizeRegAddr*(regAddr: uint16): Option[uint16] =
  let val = (regAddr mod 10000).uint16
  if val >= 1 and val <= 9999:
    result = some(val)

# ------------------------------------------------------------------------------
# Parse Response: function code 0x01/0x02
# ------------------------------------------------------------------------------
proc parseCoilStatus*(buf: openArray[uint8|char], nb: uint16): seq[bool] =
  result = newSeq[bool](nb)
  var idx = 0
  for i in 0 ..< nb.int:
    let pos = i mod 8
    let val = (buf[idx].int and (1 shl pos)) != 0
    result[i] = val
    if pos == 7:
      idx.inc

proc toseq_u16*(buf: openArray[uint8|char], pos: int, nb: uint16): seq[uint16] =
  result = newSeqOfCap[uint16](nb)
  for idx in 0 ..< nb.int:
    result.add(buf.get_be16((pos + idx * 2).uint))
