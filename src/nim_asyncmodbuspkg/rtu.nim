import std/asyncdispatch
import std/options
import std/sequtils
import std/times
import serial
import ./core
import ./util
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
    debug: bool
  ModbusRtu* = ref ModbusRtuObj

# ------------------------------------------------------------------------------
# Constructor:
# ------------------------------------------------------------------------------
proc newModbusRtu*(device: string, baud: int32 = 19200, parity = Parity.None,
    debug = false): ModbusRtu =
  let ser = newAsyncSerialPort(device)
  let rtu = new ModbusRtu
  rtu.port = device
  rtu.params = SerialParams(baud: baud, parity: parity, dataBits: 8.byte,
      stopBits: StopBits.One)
  rtu.ser = ser
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
proc read(self: ModbusRtu, timeout: int = 0): Future[Option[string]] {.async.} =
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
        break
      ch = self.fut_recv.read()
    else:
      ch = await self.fut_recv
    buf.add(ch)
    self.fut_recv = nil
    first = false

  if buf.len > 0:
    buf.setLen(buf.len)
    result = some(buf)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc sendRecv(self: ModbusRtu, payload: string, timeout: int = 0):
    Future[Option[string]] {.async.} =
  discard await self.ser.write(payload)
  await self.wait()
  result = await self.read(self.readTimeout)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc setCrc(buf: openArray[uint8], pos: uint) =
  let crc = calcCrcModbus(buf[0 ..< pos])
  buf.set_le16(pos, crc)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc checkCrc(buf: openArray[uint8|char]): bool =
  let buf_crc = buf.get_le16((buf.len - 2).uint)
  let calc_crc = calcCrcModbus(buf[0 ..< ^2])
  result = buf_crc == calc_crc

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc seSlave*(self: ModbusRtu, slaveAddr: uint8): bool =
  if slaveAddr.isValidAddress:
    self.slaveAddr = slaveAddr
    result = true

# ------------------------------------------------------------------------------
# API:
# ------------------------------------------------------------------------------
method connect*(self: ModbusRtu, timeout: uint = 0): Future[bool] {.async.} =
  if self.ser.isOpen:
    return
  let params = self.params
  self.ser.open(params.baud, params.parity, params.dataBits, params.stopBits)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
method close*(self: ModbusRtu) =
  if self.ser.isOpen:
    self.ser.close()

# ------------------------------------------------------------------------------
# Modbus/RTU Query function
# ------------------------------------------------------------------------------
proc queryCommand(self: ModbusRtu, slaveAddr: uint8, cmd: FunctionCode,
    regAddr: uint16, nb: uint16): Future[seq[char]] {.async.} =
  let addr_opt = normalizeRegAddr(regAddr)
  if addr_opt.isNone:
    return
  var buf = newSeq[uint8](8)
  buf[0] = slaveAddr
  buf[1] = cmd.uint8
  buf.set_be16(2, addr_opt.get - 1)
  buf.set_be16(4, nb)
  buf.setCrc(6)
  let payload = buf.toString()
  let res_opt = await self.sendRecv(payload)
  if res_opt.isNone:
    return
  let res_buf = res_opt.get().toSeq()
  if not res_buf.checkCrc():
    return
  result = res_buf

# ------------------------------------------------------------------------------
# Modbus/RTU Write function
# ------------------------------------------------------------------------------
proc writeCommand(self: ModbusRtu, slaveAddr: uint8, cmd: FunctionCode,
    regAddr: uint16, buf: ptr uint8, size: uint8): Future[seq[char]] {.async.} =
  let addr_opt = normalizeRegAddr(regAddr)
  if addr_opt.isNone:
    return
  let payloadLen: uint8 = 4 + size + 2
  var sendbuf = newSeq[uint8](payloadLen)
  sendbuf[0] = slaveAddr
  sendbuf[1] = cmd.uint8
  sendbuf.set_be16(2, addr_opt.get - 1)
  for idx in 0 ..< size.int:
    sendbuf[4 + idx] = buf[idx]
  sendbuf.setCrc(payloadlen - 2)
  let payload = sendbuf.toString()
  let res_opt = await self.sendRecv(payload)
  if res_opt.isNone:
    return
  let res_buf = res_opt.get.toSeq()
  if not res_buf.checkCrc():
    return
  result = res_buf

# ------------------------------------------------------------------------------
# Modbus function code 0x01: (read coil status)
# ------------------------------------------------------------------------------
method readBits*(self: ModbusRtu, target: uint8, regAddr: uint16,
    nb: uint16): Future[seq[bool]] {.async.} =
  if target.isValidAddress:
    let buf = await self.queryCommand(target, fcReadCoilStatus,
        regAddr, nb)
    if buf.len > 0:
      result = parseCoilStatus(buf[3..^3], nb)

method readBits*(self: ModbusRtu, regAddr: uint16, nb: uint16):
    Future[seq[bool]] {.async.} =
  result = await self.readBits(self.slaveAddr, regAddr, nb)

# ------------------------------------------------------------------------------
# Modbus function code 0x02: (read input bits)
# ------------------------------------------------------------------------------
method readInputBits*(self: ModbusRtu, target: uint8, regAddr: uint16,
    nb: uint16): Future[seq[bool]] {.async.} =
  if target.isValidAddress:
    let buf = await self.queryCommand(target, fcReadInputStatus,
        regAddr, nb)
    if buf.len > 0:
      result = parseCoilStatus(buf[3..^3], nb)

method readInputBits*(self: ModbusRtu, regAddr: uint16, nb: uint16):
    Future[seq[bool]] {.async.} =
  result = await self.readInputBits(self.slaveAddr, regAddr, nb)

# ------------------------------------------------------------------------------
# Modbus function code 0x03: (read holding registers)
# ------------------------------------------------------------------------------
method readRegisters*(self: ModbusRtu, target: uint8, regAddr: uint16,
    nb: uint16): Future[seq[uint16]] {.async.} =
  if target.isValidAddress:
    let buf = await self.queryCommand(target, fcReadHoldingRegister,
        regAddr, nb)
    if buf.len > 0:
      result = buf.toseq_u16(3, nb)

method readRegisters*(self: ModbusRtu, regAddr: uint16, nb: uint16):
    Future[seq[uint16]] {.async.} =
  result = await self.readRegisters(self.slaveAddr, regAddr, nb)

# ------------------------------------------------------------------------------
# Modbus function code 0x04: (read input registers)
# ------------------------------------------------------------------------------
method readInputRegisters*(self: ModbusRtu, target: uint8, regAddr: uint16,
    nb: uint16): Future[seq[uint16]] {.async.} =
  if target.isValidAddress:
    let buf = await self.queryCommand(target, fcReadInputRegister,
        regAddr, nb)
    if buf.len > 0:
      result = buf.toseq_u16(3, nb)

method readInputRegisters*(self: ModbusRtu, regAddr: uint16, nb: uint16):
    Future[seq[uint16]] {.async.} =
  result = await self.readInputRegisters(self.slaveAddr, regAddr, nb)

# ------------------------------------------------------------------------------
# Modbus function code 0x05: (force single coil)
# ------------------------------------------------------------------------------
method writeBit*(self: ModbusRtu, target: uint8, regAddr: uint16, onoff: bool):
    Future[bool] {.async.} =
  if target.isValidAddress:
    var buf = newSeq[uint8](2)
    if onoff:
      buf.set_be16(0, CoilOn.uint16)
    let res = await self.writeCommand(target, fcForceSingleCoil, regAddr,
        addr buf[0], 2)
    if res.len > 0:
      let data = res.get_be16(4)
      if ((data == CoilOn.uint16) and onoff) or
          ((data == CoilOff.uint16) and (not onoff)):
        result = true

method writeBit*(self: ModbusRtu, regAddr: uint16, onoff: bool): Future[bool] {.async.} =
  result = await self.writeBit(self.slaveAddr, regAddr, onoff)


when isMainModule:
  proc readDoValues(self: ModbusRtu) {.async.} =
    echo "--- get DO 0..7"
    let coils = await self.readBits(1, 8)
    echo coils

  proc asyncMain() {.async.} =
    let rtu = newModbusRtu("/dev/ttyS3", 19200)
    discard rtu.seSlave(2)
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
