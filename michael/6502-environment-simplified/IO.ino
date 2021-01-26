const uint32_t BUFFER_WRITE_POS = 0x0003;
const uint32_t BUFFER_READ_POS  = 0x0004;
const uint32_t CHAR_BUFFER      = 0x0200;

void initializeCharacterBuffer() {
  switchCpuToRam();
  writeRamStart();

  writeRamStep(BUFFER_WRITE_POS, 0);
  writeRamStep(BUFFER_READ_POS, 0);

  writeRamStop();
  switchRamToCpu();
}

void checkForCharacters() {
  switchCpuToRam();
  readRamStart();

  uint8_t writePos = readRamStep(BUFFER_WRITE_POS);
  uint8_t readPos  = readRamStep(BUFFER_READ_POS);

  if (writePos != readPos) {
    while (readPos != writePos) {
      uint8_t data = readRamStep(CHAR_BUFFER + readPos);
      characterOut(data);
      readPos += 1;
    }
    switchReadToWriteRam();
    writeRamStep(BUFFER_READ_POS, readPos);
    writeRamStop();
  } else {
    readRamStop();
  }

  switchRamToCpu();
}

void characterOut(uint8_t data) {
  char dataChar = (char) data;
  Serial.write(dataChar);
}
