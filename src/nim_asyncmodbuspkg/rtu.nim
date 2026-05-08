import std/asyncdispatch
import std/options
import std/sequtils
import std/times

import results
import serial

import ./core
import ./util
import ./private/asynclock
import ./private/crc16
import ./private/ptrmath


type
  SlaveAddr* = distinct range[1'u8..247'u8]

  SerialParams = object
    baud: int32
    parity: Parity
    dataBits: byte
    stopBits: StopBits

  ModbusRtuObj = object of ModbusCtxObj
    port: string
    ser: AsyncSerialPort
    params: SerialParams
    slaveAddr: uint8
    interval: int
    readTimeout: int32
    writeTimeout: int32
    fut_recv: Future[string]
    reqLock: AsyncLock
    debug: bool

  ModbusRtu* = ref ModbusRtuObj

const
  DefaultReadTimeout = 1000.int32
  DefaultWriteTimeout = 1000.int32

# ------------------------------------------------------------------------------
# Constructor:
# ------------------------------------------------------------------------------
proc newModbusRtu*(device: string, baud: int32 = 19200, parity = Parity.None, debug = false, readTimeout: int32 = DefaultReadTimeout, writeTimeout: int32 = DefaultWriteTimeout): ModbusRtu =
  let ser = newAsyncSerialPort(device)
  let rtu = new ModbusRtu

  rtu.port = device
  rtu.params = SerialParams(baud: baud, parity: parity, dataBits: 8.byte, stopBits: StopBits.One)
  rtu.ser = ser
  rtu.readTimeout = readTimeout
  rtu.writeTimeout = writeTimeout
  rtu.reqLock = newAsyncLock()

  let
    bits_per_char = 10 + (if parity == Parity.None: 0 else: 1)
    nsec_per_char = (1000_000_000 / baud).int32 * bits_per_char

  rtu.interval = ((nsec_per_char * 4) / 1000000).int32 + 1
  rtu.debug = debug
  result = rtu

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
func isValidAddress(address: uint8): bool =
  result = (address >= 1) and (address <= 247)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc wait(self: ModbusRtu) {.async.} =
  await sleepAsync(self.interval)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc read(self: ModbusRtu, timeout: int = 0, expectedLen: int = 0): Future[Result[string, ModbusError]] {.async.} =
  var
    buf = newStringOfCap(512)
    first = true

  if not self.fut_recv.isNil and self.fut_recv.finished:
    discard self.fut_recv.read()
    self.fut_recv = nil

  while true:
    if self.fut_recv.isNil:
      self.fut_recv = self.ser.read(1)

    var ch: string

    if not first or timeout > 0:
      let read_timeout = if first: timeout else: self.interval
      let received = await withTimeout(self.fut_recv, read_timeout)
      if not received:
        if buf.len == 0:
          return err(meTimeouted)
        else:
          break
      ch = self.fut_recv.read()
    else:
      ch = await self.fut_recv

    buf.add(ch)
    self.fut_recv = nil
    first = false

    if expectedLen > 0 and buf.len >= expectedLen:
      break

  if buf.len > 0:
    buf.setLen(buf.len)

  result = buf.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc setCrc(buf: openArray[uint8], pos: uint) =
  let crc = calcCrcModbus(buf[0 ..< pos])
  buf.setLe16(pos, crc)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc checkCrc(buf: openArray[uint8|char]): bool =
  let bufCrc = buf.getLe16((buf.len - 2).uint)
  let calcCrc = calcCrcModbus(buf[0 ..< ^2])
  result = bufCrc == calcCrc

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc checkRawResponse(buf: openArray[uint8|char]): ModbusError =
  if buf.len < 5:
    return meLengthError

  if not buf.checkCrc():
    return meCrcError

  let exc = checkExceptionResponse(buf, hasCrc = true)
  if exc.isSome:
    return exc.get()

  result = meSuccess

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc sendRecv(self: ModbusRtu, payload: string, timeout: int = 0, expectedLen: int = 0): Future[Result[string, ModbusError]] {.async.} =
  discard await self.ser.write(payload)
  await self.wait()

  let readTimeout =
    if timeout > 0:
      timeout
    elif self.readTimeout > 0:
      self.readTimeout.int
    else:
      DefaultReadTimeout.int

  let buf_res = await self.read(readTimeout, expectedLen)
  if buf_res.isErr:
    return buf_res

  let buf = buf_res.get().toSeq()
  let res = buf.checkRawResponse()
  if res != meSuccess:
    return res.err

  result = ok(buf_res.get())

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc setSlave*(self: ModbusRtu, slaveAddr: uint8): bool =
  if slaveAddr.isValidAddress:
    self.slaveAddr = slaveAddr
    result = true

# ------------------------------------------------------------------------------
# API:
# ------------------------------------------------------------------------------
method connect*(self: ModbusRtu, timeout: uint = 0): Future[bool] {.async.} =
  if self.ser.isOpen:
    return true

  let params = self.params
  try:
    self.ser.open(params.baud, params.parity, params.dataBits, params.stopBits)
    result = true
  except:
    discard

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
method close*(self: ModbusRtu) =
  if self.ser.isOpen:
    self.ser.close()

# ------------------------------------------------------------------------------
# Modbus/RTU Query function
# ------------------------------------------------------------------------------
method queryCommand*(self: ModbusRtu, slaveAddr: uint8, cmd: FunctionCode, regAddr: uint16, nb: uint16, timeout: int = 0): Future[Result[seq[char], ModbusError]] {.async.} =
  await self.reqLock.acquire()
  try:
    let req = checkQueryRequest(cmd, regAddr, nb)
    if req != meSuccess:
      return req.err

    let address = normalizeRegAddr(regAddr)
    var buf = newSeq[uint8](8)

    buf[0] = slaveAddr
    buf[1] = cmd.uint8
    buf.setBe16(2, address - 1)
    buf.setBe16(4, nb)
    buf.setCrc(6)

    let payload = buf.toString()
    let expectedLen = 3 + expectedReadByteCount(cmd, nb) + 2
    let res = await self.sendRecv(payload, timeout, expectedLen)
    if res.isErr:
      return res.error.err

    let res_buf = res.get().toSeq()
    if not res_buf.checkCrc():
      return meCrcError.err

    result = res_buf.ok
  finally:
    self.reqLock.release()

# ------------------------------------------------------------------------------
# Modbus/RTU Write function
# ------------------------------------------------------------------------------
proc writeCommand*(self: ModbusRtu, slaveAddr: uint8, cmd: FunctionCode, regAddr: uint16, buf: ptr uint8, size: uint8): Future[Result[seq[char], ModbusError]] {.async.} =
  await self.reqLock.acquire()
  try:
    let req = checkWriteRequest(regAddr)
    if req != meSuccess:
      return req.err

    let address = normalizeRegAddr(regAddr)
    let payloadLen: uint8 = 4 + size + 2
    var sendbuf = newSeq[uint8](payloadLen)

    sendbuf[0] = slaveAddr
    sendbuf[1] = cmd.uint8
    sendbuf.setBe16(2, address - 1)
    for idx in 0 ..< size.int:
      sendbuf[4 + idx] = buf[idx]
    sendbuf.setCrc(payloadlen - 2)

    let payload = sendbuf.toString()
    let expectedLen = 8
    let res = await self.sendRecv(payload, expectedLen = expectedLen)
    if res.isErr:
      return res.error.err

    let res_buf = res.get.toSeq()
    if not res_buf.checkCrc():
      return meCrcError.err

    result = res_buf.ok
  finally:
    self.reqLock.release()

# ------------------------------------------------------------------------------
# Modbus function code 0x01: (read coil status)
# ------------------------------------------------------------------------------
method readBits*(self: ModbusRtu, target: uint8, regAddr: uint16, nb: uint16): Future[Result[seq[bool], ModbusError]] {.async.} =
  if not target.isValidAddress:
    return meInvalidAddress.err
  else:
    let buf_res = await self.queryCommand(target, fcReadCoilStatus, regAddr, nb)
    if buf_res.isErr:
      return buf_res.error.err

    let buf = buf_res.get()
    let res = buf.checkReadResponse(target, fcReadCoilStatus, nb, hasCrc = true)
    if res != meSuccess:
      return res.err

    result = parseCoilStatus(buf[3..^3], nb).ok

method readBits*(self: ModbusRtu, regAddr: uint16, nb: uint16): Future[Result[seq[bool], ModbusError]] {.async.} =
  result = await self.readBits(self.slaveAddr, regAddr, nb)

# ------------------------------------------------------------------------------
# Modbus function code 0x02: (read input bits)
# ------------------------------------------------------------------------------
method readInputBits*(self: ModbusRtu, target: uint8, regAddr: uint16, nb: uint16): Future[Result[seq[bool], ModbusError]] {.async.} =
  if not target.isValidAddress:
    return meInvalidAddress.err
  else:
    let buf_res = await self.queryCommand(target, fcReadInputStatus, regAddr, nb)
    if buf_res.isErr:
      return buf_res.error.err

    let buf = buf_res.get()
    let res = buf.checkReadResponse(target, fcReadInputStatus, nb, hasCrc = true)
    if res != meSuccess:
      return res.err

    result = parseCoilStatus(buf[3..^3], nb).ok

method readInputBits*(self: ModbusRtu, regAddr: uint16, nb: uint16): Future[Result[seq[bool], ModbusError]] {.async.} =
  result = await self.readInputBits(self.slaveAddr, regAddr, nb)

# ------------------------------------------------------------------------------
# Modbus function code 0x03: (read holding registers)
# ------------------------------------------------------------------------------
method readRegisters*(self: ModbusRtu, target: uint8, regAddr: uint16, nb: uint16): Future[Result[seq[uint16], ModbusError]] {.async.} =
  if not target.isValidAddress:
    return meInvalidAddress.err
  else:
    let buf_res = await self.queryCommand(target, fcReadHoldingRegister, regAddr, nb)
    if buf_res.isErr:
      return buf_res.error.err

    let buf = buf_res.get()
    let res = buf.checkReadResponse(target, fcReadHoldingRegister, nb, hasCrc = true)
    if res != meSuccess:
      return res.err

    result = buf.toseqU16(3, nb).ok

method readRegisters*(self: ModbusRtu, regAddr: uint16, nb: uint16): Future[Result[seq[uint16], ModbusError]] {.async.} =
  result = await self.readRegisters(self.slaveAddr, regAddr, nb)

# ------------------------------------------------------------------------------
# Modbus function code 0x04: (read input registers)
# ------------------------------------------------------------------------------
method readInputRegisters*(self: ModbusRtu, target: uint8, regAddr: uint16, nb: uint16): Future[Result[seq[uint16], ModbusError]] {.async.} =
  if not target.isValidAddress:
    return meInvalidAddress.err
  else:
    let buf_res = await self.queryCommand(target, fcReadInputRegister, regAddr, nb)
    if buf_res.isErr:
      return buf_res.error.err

    let buf = buf_res.get()
    let res = buf.checkReadResponse(target, fcReadInputRegister, nb, hasCrc = true)
    if res != meSuccess:
      return res.err

    result = buf.toseqU16(3, nb).ok

method readInputRegisters*(self: ModbusRtu, regAddr: uint16, nb: uint16): Future[Result[seq[uint16], ModbusError]] {.async.} =
  result = await self.readInputRegisters(self.slaveAddr, regAddr, nb)

# ------------------------------------------------------------------------------
# Modbus function code 0x05: (force single coil)
# ------------------------------------------------------------------------------
method writeBit*(self: ModbusRtu, target: uint8, regAddr: uint16, onoff: bool): Future[ModbusError] {.async.} =
  if not target.isValidAddress:
    return meInvalidAddress
  else:
    let addrRes = checkRegAddr(regAddr)
    if addrRes != meSuccess:
      return addrRes

    let address = normalizeRegAddr(regAddr) - 1
    let expectData = if onoff: CoilOn.uint16 else: CoilOff.uint16
    var buf = newSeq[uint8](2)
    buf.setBe16(0, expectData)

    let res = await self.writeCommand(target, fcForceSingleCoil, regAddr, addr buf[0], 2)
    if res.isErr:
      return res.error

    let resp = res.get()
    if resp.len != 8:
      return meLengthError

    if resp[0].uint8 != target:
      return meUnknownError

    if resp[1].uint8 != fcForceSingleCoil.uint8:
      return meUnknownError

    if resp.getBe16(2) != address:
      return meUnknownError

    if resp.getBe16(4) != expectData:
      return meUnknownError

    result = meSuccess

method writeBit*(self: ModbusRtu, regAddr: uint16, onoff: bool): Future[ModbusError] {.async.} =
  result = await self.writeBit(self.slaveAddr, regAddr, onoff)


when isMainModule:
  proc readDoValues(self: ModbusRtu) {.async.} =
    echo "--- get DO 0..7"
    let coils = await self.readBits(1, 8)
    echo coils

  proc asyncMain() {.async.} =
    let rtu = newModbusRtu("/dev/ttyS3", 19200)
    discard rtu.setSlave(2)
    discard rtu.connect()

    await rtu.readDoValues()

    let status = await rtu.readInputBits(1, 8)
    echo status

    let input_regs = await rtu.readInputRegisters(30001, 17)
    echo input_regs

    echo "--- set do0 --> on"
    discard await rtu.writeBit(1, true)
    await rtu.readDoValues()

    echo "--- set do0 --> off"
    discard await rtu.writeBit(1, false)
    await rtu.readDoValues()

  waitFor asyncMain()
