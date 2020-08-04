#count      = 1024 * 4 ; works   also * 3
#count      = 1024 * 3 - 1 ; works
count      = 1024
data_value = 0
data = bytearray(count)
x = 0
for i in range(count):
  data[i] = data_value

with open("data_file.bin", "wb") as out_file:
  out_file.write(data)
