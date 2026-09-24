count      = 2
data_value = 0
data = bytearray(count)
x = 0
for i in range(count):
  data[i] = data_value

with open("data_file.bin", "wb") as out_file:
  out_file.write(data)
