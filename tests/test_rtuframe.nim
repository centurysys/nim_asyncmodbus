import std/unittest

import nim_asyncmodbuspkg/core
import nim_asyncmodbuspkg/private/crc16
import nim_asyncmodbuspkg/private/rtuframe
import nim_asyncmodbuspkg/util

suite "Modbus/RTU frame builders":
  test "builds read query frame":
    let frame = buildRtuQueryFrame(1, fcReadHoldingRegister, 40001, 2)

    check frame.len == 8
    check frame[0] == 1'u8
    check frame[1] == fcReadHoldingRegister.uint8
    check frame.getBe16(2) == 0'u16
    check frame.getBe16(4) == 2'u16
    check frame.getLe16(6) == calcCrcModbus(frame[0 ..< 6])
    check frame.getLe16(6) == 0x0bc4'u16

  test "builds read bit query frame":
    let frame = buildRtuQueryFrame(2, fcReadCoilStatus, 1, 8)

    check frame.len == 8
    check frame[0] == 2'u8
    check frame[1] == fcReadCoilStatus.uint8
    check frame.getBe16(2) == 0'u16
    check frame.getBe16(4) == 8'u16
    check frame.getLe16(6) == calcCrcModbus(frame[0 ..< 6])
    check frame.getLe16(6) == 0xff3d'u16

  test "builds write single coil frame":
    let data = @[0xff'u8, 0x00'u8]
    let frame = buildRtuWriteFrame(1, fcForceSingleCoil, 1, data)

    check frame.len == 8
    check frame[0] == 1'u8
    check frame[1] == fcForceSingleCoil.uint8
    check frame.getBe16(2) == 0'u16
    check frame.getBe16(4) == CoilOn.uint16
    check frame.getLe16(6) == calcCrcModbus(frame[0 ..< 6])
    check frame.getLe16(6) == 0x3a8c'u16

  test "write length follows data size":
    let data = @[0x12'u8, 0x34'u8, 0x56'u8, 0x78'u8]
    let frame = buildRtuWriteFrame(1, fcPresetSingleRegister, 40010, data)

    check frame.len == 10
    check frame[0] == 1'u8
    check frame[1] == fcPresetSingleRegister.uint8
    check frame.getBe16(2) == 9'u16
    check frame[4] == 0x12'u8
    check frame[5] == 0x34'u8
    check frame[6] == 0x56'u8
    check frame[7] == 0x78'u8
    check frame.getLe16(8) == calcCrcModbus(frame[0 ..< 8])
