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
  CoilStatus* = enum
    CollOff = 0x0000
    CoilOn = 0xff00


method connect*(self: ModbusCtx, timeout: uint): Future[bool] {.base, async, locks: "unknown".} =
  discard

method close*(self: ModbusCtx) {.base, locks: "unknown".} =
  discard

method read_bits*(self: ModbusCtx, regAddr: uint16, nb: uint16): Future[seq[bool]]
    {.base, async, locks: "unknown".} =
  discard

method read_input_bits*(self: ModbusCtx, regAddr: uint16, nb: uint16):
    Future[seq[bool]] {.base, async, locks: "unknown".} =
  discard

method read_registers*(self: ModbusCtx, regAddr: uint16, nb: uint16):
    Future[seq[uint16]] {.base, async, locks: "unknown".} =
  discard

method read_input_registers*(self: ModbusCtx, regAddr: uint16, nb: uint16):
    Future[seq[uint16]] {.base, async, locks: "unknown".} =
  discard

method write_bit*(self: ModbusCtx, regAddr: uint16, onoff: bool): Future[bool]
    {.base, async, locks: "unknown".} =
  discard

func normalize_regaddr*(regAddr: uint16): Option[uint16] =
  let val = (regAddr mod 10000).uint16
  if val >= 1 and val <= 9999:
    result = some(val)

# ------------------------------------------------------------------------------
# Parse Response: function code 0x01/0x02
# ------------------------------------------------------------------------------
proc parse_coil_status*(buf: openArray[uint8|char], nb: uint16): seq[bool] =
  result = newSeq[bool](nb)
  var idx = 0
  for i in 0 ..< nb.int:
    let pos = i mod 8
    let val = (buf[idx].int and (1 shl pos)) != 0
    result[i] = val
    if pos == 7:
      idx.inc

proc to_seq_u16*(buf: openArray[uint8|char], pos: int, nb: uint16): seq[uint16] =
  result = newSeqOfCap[uint16](nb)
  for idx in 0 ..< nb.int:
    result.add(buf.get_be16((pos + idx * 2).uint))
