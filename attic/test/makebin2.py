for i in range(0, 256 / 8):
  data = bytearray(range(i * 8, i * 8 + 8))
  with open("data" + str(i) + ".bin", "wb") as out_file:
    out_file.write(data)
