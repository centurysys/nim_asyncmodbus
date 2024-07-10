import std/asyncdispatch
import std/asyncnet
import std/options
import std/sequtils
import std/strutils
import ./core
import ./util
import ./private/ptrmath

type
  ModbusTcpObj = object of ModbusCtxObj
    sock: AsyncSocket
    address: string
    port: Port
    unitId: uint8
    fut_recv: Future[string]
    transactionId: uint16
    debug: bool
  ModbusTcp* = ref ModbusTcpObj

# ------------------------------------------------------------------------------
# Constructor:
# ------------------------------------------------------------------------------
proc newModbusTcp*(address: string, port: uint16, unitId: uint8 = 0): ModbusTcp =
  result = new ModbusTcp
  result.address = address
  result.port = Port(port)
  result.unitId = unitId

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
  let fut_sock = asyncnet.dial(self.address, self.port)
  if timeout > 0:
    let connected = await withTimeout(fut_sock, timeout.int)
    if not connected:
      return
    self.sock = fut_sock.read()
  else:
    self.sock = await fut_sock
  result = true

# ------------------------------------------------------------------------------
# API:
# ------------------------------------------------------------------------------
method close*(self: ModbusTcp) =
  if not self.sock.isNil:
    if self.sock.isClosed:
      self.sock.close()
    self.sock = nil

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
func checkHeader(self: ModbusTcp, header: openArray[char]): Option[int] =
  let transactionId = header.get_be16(0)
  let protocolId = header.get_be16(2)
  let length = header.get_be16(4)
  if transactionId == self.transactionId and protocolId == 0:
    result = some(length.int)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc sendRecv(self: ModbusTcp, payload: string, timeout: int = 0):
    Future[Option[string]] {.async.} =
  if not self.fut_recv.isNil and self.fut_recv.finished:
    discard self.fut_recv.read()
    self.fut_recv = nil
  if self.sock.isNil or self.sock.isClosed:
    discard await self.connect()
  await self.sock.send(payload)
  self.fut_recv = self.sock.recv(6)
  let ok = await withTimeout(self.fut_recv, timeout)
  if not ok:
    return
  let header = self.fut_recv.read()
  self.fut_recv = nil
  let payloadlen_opt = self.checkHeader(header)
  if payloadlen_opt.isNone:
    return
  let payloadlen = payloadlen_opt.get()
  let payload = await self.sock.recv(payloadlen)
  result = some(payload)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc setupHeader(self: ModbusTcp, buf: var openArray[uint8], target: uint8,
    cmd: FunctionCode) =
  self.transactionId.inc
  buf.set_be16(0, self.transactionId)
  buf[6] = target
  buf[7] = cmd.uint8

# ------------------------------------------------------------------------------
# Modbus/TCP Query function
# ------------------------------------------------------------------------------
proc queryCommand(self: ModbusTcp, target: uint8, cmd: FunctionCode, regAddr: uint16,
    nb: uint16): Future[seq[char]] {.async.} =
  let addr_opt = normalizeRegAddr(regAddr)
  if addr_opt.isNone:
    return
  const
    dataLen = 2 + 4
    payloadLen = 6 + dataLen
  var buf = newSeq[uint8](payloadLen)
  self.setupHeader(buf, target, cmd)
  buf.set_be16(8, addr_opt.get - 1)
  buf.set_be16(10, nb.uint16)
  buf.set_be16(4, dataLen)
  let payload = buf.toString()
  let res_opt = await self.sendRecv(payload, 1000)
  if res_opt.isNone:
    return
  result = res_opt.get.toSeq()

# ------------------------------------------------------------------------------
# Modbus/TCP Write function
# ------------------------------------------------------------------------------
proc writeCommand(self: ModbusTcp, target: uint8, cmd: FunctionCode, regAddr: uint16,
    buf: ptr uint8, size: uint8): Future[seq[char]] {.async.} =
  let addr_opt = normalizeRegAddr(regAddr)
  if addr_opt.isNone:
    return
  let
    dataLen: uint8 = 2 + 4 + size
    payloadLen: uint8 = 6 + dataLen
  var sendbuf = newSeq[uint8](payloadLen)
  self.setupHeader(sendbuf, target, cmd)
  sendbuf.set_be16(8, addr_opt.get - 1)
  for idx in 0 ..< size.int:
    sendbuf[10 + idx] = buf[idx]
  sendbuf.set_be16(4, dataLen)
  let payload = sendbuf.toString()
  let res_opt = await self.sendRecv(payload, 1000)
  if res_opt.isNone:
    return
  result = res_opt.get.toSeq()

# ------------------------------------------------------------------------------
# Modbus function code 0x01: (read coil status)
# ------------------------------------------------------------------------------
method readBits*(self: ModbusTcp, target: uint8, regAddr: uint16, nb: uint16):
    Future[seq[bool]] {.async.} =
  let res = await self.queryCommand(target, fcReadCoilStatus, regAddr, nb)
  if res.len >= 3:
    result = parseCoilStatus(res[3..^1], nb)

method readBits*(self: ModbusTcp, regAddr: uint16, nb: uint16): Future[seq[bool]]
    {.async.} =
  return await self.readBits(self.unitId, regaddr, nb)

# ------------------------------------------------------------------------------
# Modbus function code 0x02: (read input bits)
# ------------------------------------------------------------------------------
method readInputBits*(self: ModbusTcp, target: uint8, regAddr: uint16, nb: uint16):
    Future[seq[bool]] {.async.} =
  let res = await self.queryCommand(target, fcReadInputStatus, regAddr, nb)
  if res.len >= 3:
    result = parseCoilStatus(res[3..^1], nb)

method readInputBits*(self: ModbusTcp, regAddr: uint16, nb: uint16):
    Future[seq[bool]] {.async.} =
  return await self.readInputBits(self.unitId, regaddr, nb)

# ------------------------------------------------------------------------------
# Modbus function code 0x03: (read holding registers)
# ------------------------------------------------------------------------------
method readRegisters*(self: ModbusTcp, target: uint8, regAddr: uint16, nb: uint16):
    Future[seq[uint16]] {.async.} =
  let res = await self.queryCommand(target, fcReadHoldingRegister, regAddr, nb)
  if res.len > 0:
    result = res.toseq_u16(3, nb)

method readRegisters*(self: ModbusTcp, regAddr: uint16, nb: uint16):
    Future[seq[uint16]] {.async.} =
  return await self.readRegisters(self.unitId, regAddr, nb)

# ------------------------------------------------------------------------------
# Modbus function code 0x04: (read input registers)
# ------------------------------------------------------------------------------
method readInputRegisters*(self: ModbusTcp, target: uint8, regAddr: uint16,
    nb: uint16): Future[seq[uint16]] {.async.} =
  let res = await self.queryCommand(target, fcReadInputRegister, regAddr, nb)
  if res.len > 0:
    result = res.toseq_u16(3, nb)

method readInputRegisters*(self: ModbusTcp, regAddr: uint16, nb: uint16):
    Future[seq[uint16]] {.async.} =
  return await self.readInputRegisters(self.unitId, regAddr, nb)

# ------------------------------------------------------------------------------
# Modbus function code 0x03: (force single coil)
# ------------------------------------------------------------------------------
method writeBit*(self: ModbusTcp, target: uint8, regAddr: uint16, onoff: bool):
    Future[bool] {.async.} =
  var buf = newSeq[uint8](2)
  if onoff:
    buf.set_be16(0, CoilOn.uint16)
  let res = await self.writeCommand(target, fcForceSingleCoil, regAddr, addr buf[0], 2)
  if res.len > 0:
    let data = res.get_be16(4)
    if ((data == CoilOn.uint16) and onoff) or
        ((data == CoilOff.uint16) and (not onoff)):
      result = true

method writeBit*(self: ModbusTcp, regAddr: uint16, onoff: bool): Future[bool] {.async.} =
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
