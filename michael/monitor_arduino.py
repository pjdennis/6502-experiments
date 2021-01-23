import serial
import sys

port              = "/dev/cu.usbmodem14201"

baudrate          = 115200

ser = serial.Serial()
ser.baudrate = baudrate
ser.port = port
ser.open()

while True:
  line = ser.readline()
  print(line.decode('utf-8'), end='')
