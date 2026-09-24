import serial
import sys
import pause
from datetime import datetime, timedelta

port              = "/dev/cu.usbmodem14201"
baudrate          = 115200

#BSD checksum as calculated by cksum -o 1
def bsd_checksum(data):
  sum = 0
  for byte in data:
    sum = (sum >> 1) | (sum << 15)
    sum = (sum + byte) & 0xffff
  return sum

with open(sys.argv[1], "rb") as binaryfile:
  source_data = bytearray(binaryfile.read())

source_len = len(source_data)

if(source_len > 0xffff):
  raise ValueError("Cannot transfer more than 0xffff bytes")

length_bytes = bytearray([source_len & 0xff, (source_len >> 8) & 0xff])

#checksum = bsd_checksum(source_data)

#checksum_bytes = bytearray([checksum & 0xff, (checksum >> 8) & 0xff])

#data = length_bytes + source_data + checksum_bytes

data = source_data

number_of_bits = len(data) * (1 + 8 + 1) # start + data + stop

print("Uploading...")
print("Bps:       ", baudrate)
print("Length:    ", hex(source_len))
#print("Checksum:  ", hex(checksum))

# Duration of send allowing for 2% transfer speed loss
duration_of_send = timedelta(seconds = number_of_bits / baudrate * 1.02)

with serial.Serial(
  port=port,
  baudrate=baudrate) as ser:

  start_time = datetime.now()
  ser.write(b'l')
  ser.write(data)
  ser.flush()
  pause.until(start_time + duration_of_send)
  stop_time = datetime.now()
