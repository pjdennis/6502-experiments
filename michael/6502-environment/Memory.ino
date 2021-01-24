uint8_t MEMORY[MEMORY_SIZE];

uint8_t ROM_BUFFER[ROM_SIZE];

uint8_t memoryArea(uint16_t address) {
  if (address >= IO_START && address - IO_START < IO_SIZE) return MAP_SIMULATED_IO;
  if (ramMapped) return MAP_RAM;
  if (address >= MEMORY_START && address - MEMORY_START < MEMORY_SIZE) return MAP_SIMULATED_RAM;
  if (address >= ROM_START && address - ROM_START < ROM_SIZE) return MAP_SIMULATED_EEPROM;
  return MAP_RAM;
}

uint8_t getMemory(uint16_t address) {
  uint8_t area = memoryArea(address);
  if (area == MAP_SIMULATED_RAM) {
    return MEMORY[address];
  } else if (area == MAP_SIMULATED_EEPROM) {
    return EEPROM[address - ROM_START];
  } else if (area == MAP_RAM) {
    configureForArduinoToRam();
    uint8_t data = readFromRam(address);
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
  } else if (area == MAP_RAM) {
    configureForArduinoToRam();
    writeToRam(address, data);
    configureForCpu();
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

void copyEepromToRam() {
  for (uint16_t n = 0; n < ROM_SIZE; n += 1) {
    writeToRam(ROM_START + n, EEPROM[n]);
  }
}
