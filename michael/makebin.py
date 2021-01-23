count = 1024
data = bytearray(count)
x = 0
for i in range(count):
  data[i] = x
  x = x + 1 if x < 255 else 0

with open("data_file.bin", "wb") as out_file:
  out_file.write(data)
