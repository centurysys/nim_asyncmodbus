import std/asyncdispatch
import std/options
import std/tables
import results
export results

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

  ModbusError* = enum
    meSuccess = 0
    meInvalidFunction = 1
    meInvalidAddress = 2
    meInvalidData = 3
    meLengthError
    meCrcError
    meTimeouted
    meUnknownError

const
  ModbusErrorTable = {
    meSuccess: "Succeeded",
    meInvalidFunction: "Invalid Function",
    meInvalidAddress: "Invalid Address",
    meInvalidData: "Invalid Data",
    meLengthError: "Payload Length Error",
    meCrcError: "CRC Error",
    meTimeouted: "Timeouted",
    meUnknownError: "Unknown Error"
  }.toTable()

proc toString*(e: ModbusError): string =
  result = ModbusErrorTable[e]

method connect*(self: ModbusCtx, timeout: uint): Future[bool] {.base, async.} =
  discard

method close*(self: ModbusCtx) {.base.} =
  discard

method queryCommand*(self: ModbusCtx, slaveAddr: uint8, cmd: FunctionCode,
    regAddr: uint16, nb: uint16, timeout: int = 0): Future[Result[seq[char], ModbusError]] {.base, async.} =
  discard

method readBits*(self: ModbusCtx, target: uint8, regAddr: uint16, nb: uint16): Future[Result[seq[bool], ModbusError]] {.base, async.} =
  discard

method readBits*(self: ModbusCtx, regAddr: uint16, nb: uint16): Future[Result[seq[bool], ModbusError]] {.base, async.} =
  discard

method readInputBits*(self: ModbusCtx, target: uint8, regAddr: uint16, nb: uint16): Future[Result[seq[bool], ModbusError]] {.base, async.} =
  discard

method readInputBits*(self: ModbusCtx, regAddr: uint16, nb: uint16): Future[Result[seq[bool], ModbusError]] {.base, async.} =
  discard

method readRegisters*(self: ModbusCtx, target: uint8, regAddr: uint16, nb: uint16): Future[Result[seq[uint16], ModbusError]] {.base, async.} =
  discard

method readRegisters*(self: ModbusCtx, regAddr: uint16, nb: uint16): Future[Result[seq[uint16], ModbusError]] {.base, async.} =
  discard

method readInputRegisters*(self: ModbusCtx, target: uint8, regAddr: uint16, nb: uint16): Future[Result[seq[uint16], ModbusError]] {.base, async.} =
  discard

method readInputRegisters*(self: ModbusCtx, regAddr: uint16, nb: uint16): Future[Result[seq[uint16], ModbusError]] {.base, async.} =
  discard

method writeBit*(self: ModbusCtx, target: uint8, regAddr: uint16, onoff: bool): Future[ModbusError] {.base, async.} =
  discard

method writeBit*(self: ModbusCtx, regAddr: uint16, onoff: bool): Future[ModbusError] {.base, async.} =
  discard

const
  MaxReadBits* = 2000.uint16
  MaxReadRegisters* = 125.uint16

func normalizeRegAddr*(regAddr: uint16): uint16 =
  result = (regAddr mod 10000).uint16

func checkRegAddr*(regAddr: uint16): ModbusError =
  let address = normalizeRegAddr(regAddr)
  if address == 0:
    return meInvalidAddress

  result = meSuccess

func checkReadCount*(cmd: FunctionCode, nb: uint16): ModbusError =
  case cmd
  of fcReadCoilStatus, fcReadInputStatus:
    if nb == 0 or nb > MaxReadBits:
      return meInvalidData
  of fcReadHoldingRegister, fcReadInputRegister:
    if nb == 0 or nb > MaxReadRegisters:
      return meInvalidData
  else:
    discard

  result = meSuccess

func checkQueryRequest*(cmd: FunctionCode, regAddr: uint16, nb: uint16): ModbusError =
  let addrRes = checkRegAddr(regAddr)
  if addrRes != meSuccess:
    return addrRes

  result = checkReadCount(cmd, nb)

func checkWriteRequest*(regAddr: uint16): ModbusError =
  result = checkRegAddr(regAddr)

# ------------------------------------------------------------------------------
# Check Response
# ------------------------------------------------------------------------------
proc checkExceptionResponse*[T: uint8|char](buf: openArray[T],
    hasCrc: bool = false): Option[ModbusError] =
  if buf.len < 2:
    return

  let funcCode = buf[1].uint8
  if (funcCode and 0x80.uint8) == 0:
    return

  let expectedLen = if hasCrc: 5 else: 3
  if buf.len != expectedLen:
    return some(meLengthError)

  let exCode = buf[2].uint8
  let exc = case exCode
  of 1:
    meInvalidFunction
  of 2:
    meInvalidAddress
  of 3:
    meInvalidData
  else:
    meUnknownError
  result = some(exc)

proc checkResponse*[T: uint8|char](buf: openArray[T]): ModbusError =
  if buf.len < 2:
    return meLengthError

  let hasCrc = buf.len == 5
  let exc = checkExceptionResponse(buf, hasCrc)
  if exc.isSome:
    return exc.get()

  if buf.len < 5:
    return meLengthError

  let dataLen = buf[2].int
  if not (buf.len in [dataLen + 3, dataLen + 5]):
    return meLengthError

  result = meSuccess

func expectedReadByteCount*(cmd: FunctionCode, nb: uint16): int =
  case cmd
  of fcReadCoilStatus, fcReadInputStatus:
    result = (nb.int + 7) div 8
  of fcReadHoldingRegister, fcReadInputRegister:
    result = nb.int * 2
  else:
    result = -1

proc checkReadResponse*[T: uint8|char](buf: openArray[T], slaveAddr: uint8,
    cmd: FunctionCode, nb: uint16, hasCrc: bool = false): ModbusError =
  let resp = checkResponse(buf)
  if resp != meSuccess:
    return resp

  if buf[0].uint8 != slaveAddr:
    return meUnknownError

  if buf[1].uint8 != cmd.uint8:
    return meUnknownError

  let expectedByteCount = expectedReadByteCount(cmd, nb)
  if expectedByteCount < 0:
    return meInvalidFunction

  if buf[2].int != expectedByteCount:
    return meLengthError

  let expectedLen = expectedByteCount + 3 + (if hasCrc: 2 else: 0)
  if buf.len != expectedLen:
    return meLengthError

  result = meSuccess

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

proc toseqU16*(buf: openArray[uint8|char], pos: int, nb: uint16): seq[uint16] =
  result = newSeqOfCap[uint16](nb)
  for idx in 0 ..< nb.int:
    result.add(buf.getBe16((pos + idx * 2).uint))
