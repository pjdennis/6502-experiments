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
