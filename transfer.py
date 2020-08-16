import serial
import sys
import pause
from datetime import datetime, timedelta

#baudrate = 9600
#baudrate  = 38400
#baudrate = 19200
baudrate = 57600
stopbits_constant=serial.STOPBITS_TWO

if (stopbits_constant == serial.STOPBITS_ONE):
  stopbits_number = 1.0
else:
  stopbits_number = 2.0

with open(sys.argv[1], "rb") as binaryfile:
  data = bytearray(binaryfile.read())

number_of_bits = len(data) * (1 + 8 + stopbits_number)

# Duration of send allowing for 2% transfer speed loss
duration_of_send = timedelta(seconds = number_of_bits / baudrate * 1.02)

with serial.Serial(
  port='/dev/tty.usbserial-1410',
  baudrate=baudrate,
  stopbits=stopbits_constant) as ser:

  #ser.write(bytearray([len(data) & 0xff, (len(data) >> 8) & 0xff]))
  start_time = datetime.now()
  ser.write(data)
  ser.flush()
  pause.until(start_time + duration_of_send)
  stop_time = datetime.now()

#print("Start time:       ", start_time)
#print("Duration of send: ", duration_of_send)
#print("Stop time:        ", stop_time)
