import std/asyncdispatch
import std/asyncnet
import std/options
import std/sequtils
import std/strutils

import results

import ./core
import ./util
import ./private/asynclock
import ./private/ptrmath

type
  ModbusTcpObj = object of ModbusCtxObj
    sock: AsyncSocket
    address: string
    port: Port
    unitId: uint8
    fut_recv: Future[string]
    transactionId: uint16
    reqLock: AsyncLock
    debug: bool

  ModbusTcp* = ref ModbusTcpObj

const
  MaxTcpPayloadLength = 254
  DefaultTcpTimeout = 1000

# ------------------------------------------------------------------------------
# Constructor:
# ------------------------------------------------------------------------------
proc newModbusTcp*(address: string, port: uint16, unitId: uint8 = 0): ModbusTcp =
  result = new ModbusTcp
  result.address = address
  result.port = Port(port)
  result.unitId = unitId
  result.reqLock = newAsyncLock()

# ------------------------------------------------------------------------------
# API:
# ------------------------------------------------------------------------------
method connect*(self: ModbusTcp, timeout: uint = 0): Future[bool] {.async.} =
  if not self.sock.isNil:
    if self.sock.isClosed:
      self.sock.close()
      self.sock = nil
    else:
      # already connected
      return true

  try:
    let fut_sock = asyncnet.dial(self.address, self.port)
    if timeout > 0:
      let connected = await withTimeout(fut_sock, timeout.int)
      if not connected:
        return false
      self.sock = fut_sock.read()
    else:
      self.sock = await fut_sock
    result = true
  except:
    self.sock = nil
    result = false

# ------------------------------------------------------------------------------
# API:
# ------------------------------------------------------------------------------
method close*(self: ModbusTcp) =
  if not self.sock.isNil:
    if not self.sock.isClosed:
      self.sock.close()
    self.sock = nil
  self.fut_recv = nil

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
func checkHeader(self: ModbusTcp, header: openArray[char]): Result[int, ModbusError] =
  if header.len != 6:
    return meLengthError.err

  let transactionId = header.getBe16(0)
  let protocolId = header.getBe16(2)
  let length = header.getBe16(4)

  if transactionId != self.transactionId:
    return meUnknownError.err

  if protocolId != 0:
    return meUnknownError.err

  if length < 3 or length > MaxTcpPayloadLength:
    return meLengthError.err

  result = length.int.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc readExact(self: ModbusTcp, size: int, timeout: int = 0):
  Future[Result[string, ModbusError]] {.async.} =
  var buf = newStringOfCap(size)

  while buf.len < size:
    self.fut_recv = self.sock.recv(size - buf.len)

    var chunk = ""
    if timeout > 0:
      let ok = await withTimeout(self.fut_recv, timeout)
      if not ok:
        self.close()
        return meTimeouted.err
      chunk = self.fut_recv.read()
    else:
      chunk = await self.fut_recv

    self.fut_recv = nil
    if chunk.len == 0:
      self.close()
      return meLengthError.err

    buf.add(chunk)

  result = buf.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc sendRecv(self: ModbusTcp, payload: string, timeout: int = 0):
  Future[Result[string, ModbusError]] {.async.} =
  if not self.fut_recv.isNil and self.fut_recv.finished:
    discard self.fut_recv.read()
    self.fut_recv = nil

  let recvTimeout =
    if timeout > 0:
      timeout
    else:
      DefaultTcpTimeout

  if self.sock.isNil or self.sock.isClosed:
    let connected = await self.connect(recvTimeout.uint)
    if not connected:
      return meTimeouted.err

  try:
    await self.sock.send(payload)
  except:
    self.close()
    return meUnknownError.err

  let header_res = await self.readExact(6, recvTimeout)
  if header_res.isErr:
    return header_res.error.err

  let header = header_res.get()
  let payloadlen_res = self.checkHeader(header)
  if payloadlen_res.isErr:
    self.close()
    return payloadlen_res.error.err

  let payloadlen = payloadlen_res.get()
  let payload_res = await self.readExact(payloadlen, recvTimeout)
  if payload_res.isErr:
    return payload_res.error.err

  let response = payload_res.get()
  let exc = checkExceptionResponse(response)
  if exc.isSome:
    return exc.get().err

  result = response.ok

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc setupHeader(self: ModbusTcp, buf: var openArray[uint8], target: uint8,
    cmd: FunctionCode) =
  self.transactionId.inc
  buf.setBe16(0, self.transactionId)
  buf[6] = target
  buf[7] = cmd.uint8

# ------------------------------------------------------------------------------
# Modbus/TCP Query function
# ------------------------------------------------------------------------------
method queryCommand*(self: ModbusTcp, slaveAddr: uint8, cmd: FunctionCode,
    regAddr: uint16, nb: uint16, timeout: int = 0):
    Future[Result[seq[char], ModbusError]] {.async.} =
  await self.reqLock.acquire()
  try:
    let req = checkQueryRequest(cmd, regAddr, nb)
    if req != meSuccess:
      return req.err

    let address = normalizeRegAddr(regAddr)
    const
      dataLen = 2 + 4
      payloadLen = 6 + dataLen

    var buf = newSeq[uint8](payloadLen)
    self.setupHeader(buf, slaveAddr, cmd)
    buf.setBe16(8, address - 1)
    buf.setBe16(10, nb.uint16)
    buf.setBe16(4, dataLen)

    let payload = buf.toString()
    let res = await self.sendRecv(payload, timeout)
    if res.isErr:
      return res.error.err

    result = res.get.toSeq().ok
  finally:
    self.reqLock.release()

# ------------------------------------------------------------------------------
# Modbus/TCP Write function
# ------------------------------------------------------------------------------
proc writeCommand*(self: ModbusTcp, target: uint8, cmd: FunctionCode, regAddr: uint16,
    buf: ptr uint8, size: uint8): Future[Result[seq[char], ModbusError]] {.async.} =
  await self.reqLock.acquire()
  try:
    let req = checkWriteRequest(regAddr)
    if req != meSuccess:
      return req.err

    let address = normalizeRegAddr(regAddr)
    let
      dataLen: uint8 = 2 + 2 + size
      payloadLen: uint8 = 6 + dataLen

    var sendbuf = newSeq[uint8](payloadLen)
    self.setupHeader(sendbuf, target, cmd)
    sendbuf.setBe16(8, address - 1)
    for idx in 0 ..< size.int:
      sendbuf[10 + idx] = buf[idx]
    sendbuf.setBe16(4, dataLen)

    let payload = sendbuf.toString()
    let res = await self.sendRecv(payload)
    if res.isErr:
      return res.error.err

    result = res.get.toSeq().ok
  finally:
    self.reqLock.release()

# ------------------------------------------------------------------------------
# Modbus function code 0x01: (read coil status)
# ------------------------------------------------------------------------------
method readBits*(self: ModbusTcp, target: uint8, regAddr: uint16, nb: uint16):
    Future[Result[seq[bool], ModbusError]] {.async.} =
  let res = await self.queryCommand(target, fcReadCoilStatus, regAddr, nb)
  if res.isErr:
    return res.error.err

  let payload = res.get()
  let resp = checkReadResponse(payload, target, fcReadCoilStatus, nb)
  if resp != meSuccess:
    return resp.err

  result = parseCoilStatus(payload[3..^1], nb).ok

method readBits*(self: ModbusTcp, regAddr: uint16, nb: uint16):
    Future[Result[seq[bool], ModbusError]] {.async.} =
  return await self.readBits(self.unitId, regaddr, nb)

# ------------------------------------------------------------------------------
# Modbus function code 0x02: (read input bits)
# ------------------------------------------------------------------------------
method readInputBits*(self: ModbusTcp, target: uint8, regAddr: uint16, nb: uint16):
    Future[Result[seq[bool], ModbusError]] {.async.} =
  let res = await self.queryCommand(target, fcReadInputStatus, regAddr, nb)
  if res.isErr:
    return res.error.err

  let payload = res.get()
  let resp = checkReadResponse(payload, target, fcReadInputStatus, nb)
  if resp != meSuccess:
    return resp.err

  result = parseCoilStatus(payload[3..^1], nb).ok

method readInputBits*(self: ModbusTcp, regAddr: uint16, nb: uint16):
    Future[Result[seq[bool], ModbusError]] {.async.} =
  return await self.readInputBits(self.unitId, regaddr, nb)

# ------------------------------------------------------------------------------
# Modbus function code 0x03: (read holding registers)
# ------------------------------------------------------------------------------
method readRegisters*(self: ModbusTcp, target: uint8, regAddr: uint16, nb: uint16):
    Future[Result[seq[uint16], ModbusError]] {.async.} =
  let res = await self.queryCommand(target, fcReadHoldingRegister, regAddr, nb)
  if res.isErr:
    return res.error.err

  let payload = res.get()
  let resp = checkReadResponse(payload, target, fcReadHoldingRegister, nb)
  if resp != meSuccess:
    return resp.err

  result = payload.toseqU16(3, nb).ok

method readRegisters*(self: ModbusTcp, regAddr: uint16, nb: uint16):
    Future[Result[seq[uint16], ModbusError]] {.async.} =
  return await self.readRegisters(self.unitId, regAddr, nb)

# ------------------------------------------------------------------------------
# Modbus function code 0x04: (read input registers)
# ------------------------------------------------------------------------------
method readInputRegisters*(self: ModbusTcp, target: uint8, regAddr: uint16,
    nb: uint16): Future[Result[seq[uint16], ModbusError]] {.async.} =
  let res = await self.queryCommand(target, fcReadInputRegister, regAddr, nb)
  if res.isErr:
    return res.error.err

  let payload = res.get()
  let resp = checkReadResponse(payload, target, fcReadInputRegister, nb)
  if resp != meSuccess:
    return resp.err

  result = payload.toseqU16(3, nb).ok

method readInputRegisters*(self: ModbusTcp, regAddr: uint16, nb: uint16):
    Future[Result[seq[uint16], ModbusError]] {.async.} =
  return await self.readInputRegisters(self.unitId, regAddr, nb)

# ------------------------------------------------------------------------------
# Modbus function code 0x05: (force single coil)
# ------------------------------------------------------------------------------
method writeBit*(self: ModbusTcp, target: uint8, regAddr: uint16, onoff: bool):
    Future[ModbusError] {.async.} =
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
  if resp.len != 6:
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

method writeBit*(self: ModbusTcp, regAddr: uint16, onoff: bool): Future[ModbusError] {.async.} =
  return await self.writeBit(self.unitId, regAddr, onoff)

when isMainModule:
  proc readDoValues(self: ModbusTcp) {.async.} =
    echo "--- get DO 0..7"
    let coils = await self.readBits(1, 8)
    echo coils

  proc asyncMain() {.async.} =
    let tcp = newModbusTcp("172.16.1.29", 502)
    #discard await tcp.connect()
    await tcp.readDoValues()

    let input_regs = await tcp.readInputRegisters(30001, 17)
    echo input_regs

    echo "--- set do0 --> on"
    discard await tcp.writeBit(1, true)
    await tcp.readDoValues()

    echo "--- set do0 --> off"
    discard await tcp.writeBit(1, false)
    await tcp.readDoValues()

  waitFor asyncMain()
