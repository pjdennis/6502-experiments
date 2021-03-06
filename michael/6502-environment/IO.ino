const uint32_t BUFFER_WRITE_POS = 0x0003;
const uint32_t BUFFER_READ_POS  = 0x0004;
const uint32_t CHAR_BUFFER      = 0x0200;

void putIo(uint16_t address, uint8_t data) {
  if (address = COUT_PORT) {
    characterOut(data);
  }
}

void characterOut(uint8_t data) {
  char dataChar = (char) data;
  if (shouldShowState()) {
    char buffer[7];
    Serial.write("CPU wrote the value: ");
    sprintf(buffer, "%c (%02x)", isPrintable(dataChar) ? dataChar : '.', data);
    Serial.println(buffer);
  } else {
    Serial.write(dataChar);
  }
}

void checkForCharacters() {
  uint8_t writePos = getMemory(BUFFER_WRITE_POS);
  uint8_t readPos  = getMemory(BUFFER_READ_POS);

  if (writePos != readPos) {
    while (readPos != writePos) {
      uint8_t data = getMemory(CHAR_BUFFER + readPos);
      characterOut(data);
      readPos += 1;
    }
    putMemory(BUFFER_READ_POS, readPos);
  }
}

void initializeCharacterBuffer() {
  putMemory(BUFFER_WRITE_POS, 0);
  putMemory(BUFFER_READ_POS, 0);
}
