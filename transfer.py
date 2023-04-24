import getopt
import serial
import sys
import pause
from datetime import datetime, timedelta

try:
  options, args = getopt.getopt(sys.argv[1:], shortopts="", longopts=["noreset", "stopbits=", "port=", "baudrate="])
except getopt.GetoptError as err:
  print("Error:", err)  # will print something like "option -a not recognized"
  sys.exit(2)

input_file = args[0]

noreset  = False
stopbits = serial.STOPBITS_ONE
port     = None
baudrate = None

for option, value in options:
  if option == "--noreset":
    noreset = True
  elif option == "--stopbits":
    if value == "1":
      stopbits = serial.STOPBITS_ONE
    elif value == "2":
      stopbits = serial.STOPBITS_TWO
    else:
      print("Error the --stopbits option value must be 1 or 2")
      sys.exit(2)
  elif option == "--port":
    port = value
  elif option == "--baudrate":
    try:
      baudrate = int(value)
    except ValueError:
      print("Error: the --baudrate argument must be a valid integer value")
      sys.exit(2)

if port is None:
  print("Error: the --port argument must be specified")
  sys.exit(2)

if baudrate is None:
  print("Error: the --baudrate argment must be specified")
  sys.exit(2)

#BSD checksum as calculated by cksum -o 1
def bsd_checksum(data):
  sum = 0
  for byte in data:
    sum = (sum >> 1) | (sum << 15)
    sum = (sum + byte) & 0xffff
  return sum

with open(input_file, "rb") as binaryfile:
  source_data = bytearray(binaryfile.read())

source_len = len(source_data)

if(source_len > 0xffff):
  print("Error: cannot transfer more than 0xffff bytes")
  sys.exit(1)

length_bytes = bytearray([source_len & 0xff, (source_len >> 8) & 0xff])
checksum = bsd_checksum(source_data)
checksum_bytes = bytearray([checksum & 0xff, (checksum >> 8) & 0xff])
data = length_bytes + source_data + checksum_bytes
number_of_bits = len(data) * (1 + 8 + stopbits)

# Duration of send allowing for 2% transfer speed loss
duration_of_send = timedelta(seconds = number_of_bits / baudrate * 1.02)

with serial.Serial(baudrate=baudrate, stopbits=stopbits) as ser:
  ser.port = port
  ser.dtr = False
  ser.open()

  if (not noreset):
    ser.dtr=True
    pause.until(datetime.now() + timedelta(seconds=0.1))
    ser.dtr=False
    pause.until(datetime.now() + timedelta(seconds=0.2))

  start_time = datetime.now()
  ser.write(data)
  ser.flush()
  pause.until(start_time + duration_of_send)
  stop_time = datetime.now()
