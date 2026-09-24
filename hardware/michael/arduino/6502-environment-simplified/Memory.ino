#include <EEPROM.h>

const uint16_t ROM_START    = 0xfc00;
const uint16_t ROM_SIZE     = 0x0400;

uint8_t ROM_BUFFER[ROM_SIZE];

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
  switchCpuToRam();
  writeRamStart();

  for (uint16_t n = 0; n < ROM_SIZE; n += 1) {
    writeRamStep(ROM_START + n, EEPROM[n]);
  }

  writeRamStop();
  switchRamToCpu();
}

void dumpMemoryLow() {
  dumpMemory(0x0000, 0x0400);
}

void dumpMemoryHigh() {
  dumpMemory(ROM_START, ROM_SIZE);
}
