import nim_asyncmodbuspkg/[core, rtu, tcp]
export rtu, tcp
export FunctionCode, DiagCode


when isMainModule:
  import std/asyncdispatch

  proc readDoValues(self: ModbusCtx) {.async.} =
    echo "--- get DO 0..7"
    let coils = await self.readBits(1, 8)
    echo coils

  proc test_modbus(self: ModbusCtx) {.async.} =
    await self.readDoValues()
    let status = await self.readInputBits(1, 8)
    echo status
    let input_regs = await self.readInputRegisters(30001, 17)
    echo input_regs
    echo "--- set do0 --> on"
    discard await self.writeBit(1, true)
    await self.readDoValues()
    echo "--- set do0 --> off"
    discard await self.writeBit(1, false)
    await self.readDoValues()

  proc asyncMain() {.async.} =
    echo "--- Test Modbus/RTU ---"
    let rtu = newModbusRtu("/dev/tnt0", 19200)
    discard rtu.seSlave(2)
    discard rtu.connect()
    await rtu.test_modbus()

    echo "--- Test Modbus/TCP ---"
    let tcp = newModbusTcp("172.16.1.29", 502)
    await tcp.test_modbus()

  waitFor asyncMain()
