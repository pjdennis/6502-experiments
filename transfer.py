import serial
import sys
import time

with open(sys.argv[1], "rb") as binaryfile:
  data = bytearray(binaryfile.read())

with serial.Serial(
  port='/dev/tty.usbserial-1410',
  baudrate=19200,
  stopbits=serial.STOPBITS_TWO) as ser:

  #ser.write(bytearray([len(data) & 0xff, (len(data) >> 8) & 0xff]))
  ser.write(data)
  time.sleep(0.25)
