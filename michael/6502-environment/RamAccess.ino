void writeToRam(uint16_t address, uint8_t data) {
  writeToAddressBus(address);
  configureDataBus(OUTPUT);
  writeToDataBus(data);
  setWrite(true);
  selectRamChip(true);
  delayFor(1);
  selectRamChip(false);
  setWrite(false);
  configureDataBus(INPUT_PULLUP);
}

uint8_t readFromRam(uint16_t address) {
  writeToAddressBus(address);
  selectRamChip(true);
  delayFor(1);
  uint8_t data = readFromDataBus();
  selectRamChip(false);
  return data;
}

void testRam() {
  writeToRam(0x0000, 0x55);
  writeToRam(0x0001, 0x88);
  showHex(readFromRam(0x0000));
  writeToRam(0x0000, 0x42);
  showHex(readFromRam(0x0001));
  showHex(readFromRam(0x0000));
}

void showHex(uint8_t x) {
  char buffer[3];
  sprintf(buffer, "%02x", x);
  Serial.println(buffer);
}
