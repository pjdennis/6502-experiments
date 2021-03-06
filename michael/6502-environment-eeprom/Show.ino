void maybeShowState() {
  if (shouldShowState()) {
      uint16_t address = readFromAddressBus();
      uint8_t data = readFromDataBus();
      bool rd_wrb = digitalRead(RD_WRB);
      uint8_t area = memoryArea(address);

      showState(address, data, rd_wrb ? 'r' : 'W', area == MAP_EEPROM ? 'E' : 'S');
  }
}

bool shouldShowState() {
  return runMode == RUN_MODE_SLOW || !processorRunning;
}

void showState(uint16_t address, uint8_t data, char operation, char area) {
  for (int n = 15; n >= 0; n -= 1) {
    Serial.print(bitRead(address, n));
  }

  Serial.print("   ");

  for (int n = 7; n >= 0; n -= 1) {
    Serial.print(bitRead(data, n));
  }

  char dataChar = (char) data;

  char output[24];
  sprintf(output, "   %04x %c  %c %02x .. %c %c",
    address,
    isPrintable(dataChar) ? dataChar : ' ',
    operation,
    data,
    area,
    probeIsHigh() ? 'H' : 'L');

  Serial.print(output);

  Serial.println();
}

void dumpMemory(uint16_t start, uint16_t count) {
  const unsigned int bytesPerLine = 32;
  char buffer[6];
  Serial.println("Memory dump:");
  for (uint16_t address = start; address - start < count; address += bytesPerLine) {
    sprintf(buffer, "%04x ", address);
    Serial.print(buffer);
    for (unsigned int n = 0; n < bytesPerLine; n += 1) {
      sprintf(buffer, " %02x", getMemory(address + n));
      Serial.print(buffer);
    }
    Serial.print("  ");
    for (unsigned int n = 0; n < bytesPerLine; n += 1) {
      char dataChar = (char) getMemory(address + n);
      Serial.print(isPrintable(dataChar) ? dataChar : '.');
    }
    Serial.println();
  }
}

void dumpMemory2(uint16_t start, uint16_t count) {
  const unsigned int bytesPerLine = 32;
  char buffer[6];
  Serial.println("EEPROM dump:");
  configureForArduinoToEeprom();
  for (uint16_t address = start; address - start < count; address += bytesPerLine) {
    sprintf(buffer, "%04x ", address);
    Serial.print(buffer);
    for (unsigned int n = 0; n < bytesPerLine; n += 1) {
      sprintf(buffer, " %02x", readFromEeprom(address + n));
      Serial.print(buffer);
    }
    Serial.print("  ");
    for (unsigned int n = 0; n < bytesPerLine; n += 1) {
      char dataChar = (char) readFromEeprom(address + n);
      Serial.print(isPrintable(dataChar) ? dataChar : '.');
    }
    Serial.println();
  }
  configureForCpu();
}
