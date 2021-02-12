uint8_t readFromEeprom(uint16_t address) {
  writeToAddressBus(address);
  delayFor(1);
  return readFromDataBus();
}

void writeToEeprom(uint16_t address, uint8_t data) {
  outputEnableEepromChip(false);
  writeToAddressBus(address);
  configureDataBus(OUTPUT);
  writeToDataBus(data);
  setWriteEeprom(true);
  delayFor(1);
  setWriteEeprom(false);
  configureDataBus(INPUT);
  outputEnableEepromChip(true);
}

void writePageToEeprom(uint16_t address, const uint8_t* pData) {
  outputEnableEepromChip(false);
  configureDataBus(OUTPUT);
  for (int i = 0; i < 64; i++) {
    writeToAddressBus(address++);
    writeToDataBus(*pData++);
    setWriteEeprom(true);
    setWriteEeprom(false);
  }
  configureDataBus(INPUT);
  outputEnableEepromChip(true);
  address--;
  pData--;
  while(readFromEeprom(address) != *pData)
    ;
}

void turnOffEepromWriteProtection() {
  writeToEeprom(0x5555, 0xaa);
  writeToEeprom(0x2aaa, 0x55);
  writeToEeprom(0x5555, 0x80);
  writeToEeprom(0x5555, 0xaa);
  writeToEeprom(0x2aaa, 0x55);
  writeToEeprom(0x5555, 0x20);
}

void dataProtectionEnable() {
  writeToEeprom(0x5555, 0xaa);
  writeToEeprom(0x2aaa, 0x55);
  writeToEeprom(0x5555, 0xa0);  
}

void testEepromPageWrite() {
  uint8_t page[64];
  for (int n = 0; n <= 64; n += 1) {
    page[n] = n + 2;
  }
  writePageToEeprom(0xfe00, page);
  delayFor(1000* 10);
  dumpMemory(ROM_START, ROM_SIZE);
}

void testEeprom() {
  uint8_t data = readFromEeprom(0xfff0);
  Serial.print("Value before: "); showHex(data); Serial.println();
  data -= 1;

  uint32_t counter = 0;
  writeToEeprom(0xfff0, data);
  while (readFromEeprom(0xfff0) != data) {
    counter += 1;
  }
  Serial.print("Counter: "); Serial.println(counter);
  data = readFromEeprom(0xfff0);
  Serial.print("Value after:  "); showHex(data); Serial.println();
}

void showHex(uint8_t x) {
  char buffer[3];
  sprintf(buffer, "%02x", x);
  Serial.print(buffer);
}
