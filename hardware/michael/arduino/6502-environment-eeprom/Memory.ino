uint8_t MEMORY[MEMORY_SIZE];

uint8_t ROM_BUFFER[ROM_SIZE];

uint8_t memoryArea(uint16_t address) {
  if (address >= IO_START && address - IO_START < IO_SIZE) return MAP_SIMULATED_IO;
  if (address >= MEMORY_START && address - MEMORY_START < MEMORY_SIZE) return MAP_SIMULATED_RAM;
  if (eepromMapped) {
    if (address >= EEPROM_START && address - EEPROM_START < EEPROM_SIZE) {
      return MAP_EEPROM;
    }
  } else {
    if (address >= ROM_START && address - ROM_START < ROM_SIZE) {
      return MAP_SIMULATED_EEPROM;
    }
  }
  return MAP_NONE;
}

void clearMemory() {
  for (uint16_t n = 0; n <= MEMORY_SIZE; n += 1) {
    MEMORY[n] = 0;
  }
  Serial.println("Memory cleared.");
}

uint8_t getMemory(uint16_t address) {
  uint8_t area = memoryArea(address);
  if (area == MAP_SIMULATED_RAM) {
    return MEMORY[address];
  } else if (area == MAP_SIMULATED_EEPROM) {
    return EEPROM[address - ROM_START];
  } else if (area == MAP_EEPROM) {
    configureForArduinoToEeprom();
    uint8_t data = readFromEeprom(address);
    configureForCpu();
    return data;
  }
  return 0;
}

void putMemory(uint16_t address, uint8_t data) {
  uint8_t area = memoryArea(address);
  if (area == MAP_SIMULATED_RAM) {
    MEMORY[address] = data;
  } else if (area == MAP_SIMULATED_IO) {
    putIo(address, data);
  }
}

void loadMemoryFromSerial() {
  Serial.println("Waiting for data...");
  for (uint16_t n = 0; n < ROM_SIZE; n += 1) {
    while (!Serial.available())
      ;
    uint8_t data = (uint8_t) Serial.read();
    ROM_BUFFER[n] = data;
  }
  for (uint16_t n = 0; n < ROM_SIZE; n += 1) {
    EEPROM[n] = ROM_BUFFER[n];
  }
  Serial.println("Data loaded.");
}

void copyArduinoEepromToEeprom() {
  configureForArduinoToEeprom();

  for (uint16_t n = 0; n < ROM_SIZE; n += 1) {
    ROM_BUFFER[n] = EEPROM[n];
  }
  
  for (uint16_t n = 0; n < ROM_SIZE; n += 64) {
    writePageToEeprom(ROM_START + n, (ROM_BUFFER + n));
  }
  configureForCpu();
}
