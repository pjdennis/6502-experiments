data = bytearray(431-256)
x = 0
for i in range(431-256):
  data[i] = x
  x = x + 1
  if (x == 256):
    x = 0

with open("data_plus.bin", "wb") as out_file:
  out_file.write(data)
