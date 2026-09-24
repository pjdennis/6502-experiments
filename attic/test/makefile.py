data = bytearray([
  0b00000001, 0b00000100
  ])

with open("test.bin", "wb") as out_file:
  out_file.write(data)
