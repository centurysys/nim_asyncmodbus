import std/unittest

import nim_asyncmodbuspkg/core
import nim_asyncmodbuspkg/private/tcpframe
import nim_asyncmodbuspkg/util

suite "Modbus/TCP frame builders":
  test "builds read query frame":
    let frame = buildTcpQueryFrame(0x1234'u16, 1, fcReadHoldingRegister, 40001, 2)

    check frame.len == 12
    check frame.getBe16(0) == 0x1234'u16
    check frame.getBe16(2) == 0'u16
    check frame.getBe16(4) == 6'u16
    check frame[6] == 1'u8
    check frame[7] == fcReadHoldingRegister.uint8
    check frame.getBe16(8) == 0'u16
    check frame.getBe16(10) == 2'u16

  test "builds write single coil frame":
    let data = @[0xff'u8, 0x00'u8]
    let frame = buildTcpWriteFrame(1, 2, fcForceSingleCoil, 1, data)

    check frame.len == 12
    check frame.getBe16(0) == 1'u16
    check frame.getBe16(2) == 0'u16
    check frame.getBe16(4) == 6'u16
    check frame[6] == 2'u8
    check frame[7] == fcForceSingleCoil.uint8
    check frame.getBe16(8) == 0'u16
    check frame.getBe16(10) == CoilOn.uint16

  test "write length follows data size":
    let data = @[0x12'u8, 0x34'u8, 0x56'u8, 0x78'u8]
    let frame = buildTcpWriteFrame(2, 1, fcPresetSingleRegister, 40010, data)

    check frame.len == 14
    check frame.getBe16(4) == 8'u16
    check frame.getBe16(8) == 9'u16
    check frame[10] == 0x12'u8
    check frame[11] == 0x34'u8
    check frame[12] == 0x56'u8
    check frame[13] == 0x78'u8
