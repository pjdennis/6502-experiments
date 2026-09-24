data = bytearray(range(0,256))

with open("data.bin", "wb") as out_file:
  out_file.write(data)
