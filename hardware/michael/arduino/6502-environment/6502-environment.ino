#include <EEPROM.h>

const uint16_t MEMORY_START = 0x0000;
const uint16_t MEMORY_SIZE  = 0x0400;
const uint16_t ROM_START    = 0xfc00;
const uint16_t ROM_SIZE     = 0x0400;
const uint16_t IO_START     = 0x7000;
const uint16_t IO_SIZE      = 0x0100;

const uint8_t MAP_SIMULATED_RAM    = 1;
const uint8_t MAP_SIMULATED_EEPROM = 2;
const uint8_t MAP_SIMULATED_IO     = 3;
const uint8_t MAP_RAM              = 4;

const uint16_t COUT_PORT = IO_START;

const uint32_t TClockWidthLowSlow   = 100000;
const uint32_t TClockWidthHighSlow  = 100000;
const uint32_t TClockWidthLowFast   = 2;
const uint32_t TClockWidthHighFast  = 2;
const uint32_t TClockWidthFree      = 0;
const uint32_t THoldRead            = 1;

const uint8_t RUN_MODE_SLOW = 1;
const uint8_t RUN_MODE_FAST = 2;
const uint8_t RUN_MODE_FREE = 3;

const uint16_t POLL_INTERVAL = 1000;

uint32_t TClockWidthLow;
uint32_t TClockWidthHigh;
uint8_t  runMode;

bool processorRunning = false;
bool ramMapped        = false;
uint16_t pollCounter  = 0;

void setup() {
  configurePinsSafe();

  Serial.begin(115200);
  Serial.println("---- Ardino restarted ----");

  configureForArduinoToRam();
  testRam();

  configureForCpu();
  ramMapped = true;
  setRunMode(RUN_MODE_FREE);
  boot();
}

void loop() {
  if (Serial.available()) {
    handleSerialCommand();
  } else if (processorRunning) {
    performClockCycle();
  }
}
