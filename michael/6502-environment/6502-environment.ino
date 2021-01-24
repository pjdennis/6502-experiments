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

uint8_t MEMORY[MEMORY_SIZE];

uint8_t ROM_BUFFER[ROM_SIZE];

const uint32_t TClockWidthLowSlow   = 100000;
const uint32_t TClockWidthHighSlow  = 100000;
const uint32_t TClockWidthLowFast   = 2;
const uint32_t TClockWidthHighFast  = 2;
const uint32_t THoldRead            = 1;

uint32_t TClockWidthLow;
uint32_t TClockWidthHigh;
bool     fullSpeed;

bool processorRunning = false;
bool ramMapped        = false;

void setup() {
  configureSafe();

  Serial.begin(115200);
  Serial.println("---- Ardino restarted ----");

  configureForArduinoToRam();
  testRam();

  configureForCpu();
  setFullSpeed(false);
  resetCPU();
}

void loop() {
  if (Serial.available()) {
    handleSerialCommand();
  } else if (processorRunning) {
    performClockCycle();
  }
}
