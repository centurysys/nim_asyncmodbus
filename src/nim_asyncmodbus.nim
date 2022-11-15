import nim_asyncmodbuspkg/[core, rtu, tcp]
export rtu, tcp
export FunctionCode, DiagCode


when isMainModule:
  import std/asyncdispatch

  proc read_do_values(self: ModbusCtx) {.async.} =
    echo "--- get DO 0..7"
    let coils = await self.read_bits(1, 8)
    echo coils

  proc test_modbus(self: ModbusCtx) {.async.} =
    await self.read_do_values()
    let status = await self.read_input_bits(1, 8)
    echo status
    let input_regs = await self.read_input_registers(30001, 17)
    echo input_regs
    echo "--- set do0 --> on"
    discard await self.write_bit(1, true)
    await self.read_do_values()
    echo "--- set do0 --> off"
    discard await self.write_bit(1, false)
    await self.read_do_values()

  proc asyncMain() {.async.} =
    echo "--- Test Modbus/RTU ---"
    let rtu = newModbusRtu("/dev/ttyS3", 19200)
    discard rtu.set_slave(2)
    discard rtu.connect()
    await rtu.test_modbus()

    echo "--- Test Modbus/TCP ---"
    let tcp = newModbusTcp("172.16.1.29", 502)
    await tcp.test_modbus()

  waitFor asyncMain()
