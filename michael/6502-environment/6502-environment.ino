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

void handleSerialCommand() {
    int c = Serial.read();
    switch (c) {
      case 'f': // Set Full speed
        setFullSpeed(true);
        Serial.println("Full speed selected.");
        break;
      case 'w': // Set sloW speed
        setFullSpeed(false);
        Serial.println("Slow speed selected.");
        break;
      case 's': // Make processor Stop
        processorRunning = false;
        Serial.println("Processor stopped.");
        break;
      case 'g': // Make processor Go
        processorRunning = true;
        Serial.println("Processor started.");
        break;
      case 'c': // Perform a clock Cycle
        performClockCycle();
        break;
      case 'r': // Perform CPU Reset
        resetCPU();
        break;
      case 'l': // Perform Load of memory from serial
        loadMemoryFromSerial();
        break;
      case 'd': // Perform memory Dump from start of memory
        dumpMemory(MEMORY_START, MEMORY_SIZE);
        break;
      case 'm': // Perform memory dump from roM area
        dumpMemory(ROM_START, ROM_SIZE);
        break;
      case 'a': // Switch to real rAm
        configureForArduinoToRam();
        copyEepromToRam();
        configureForCpu();
        ramMapped = true;
        Serial.println("Switched to real memory and copied ROM over.");
        break;
      case 'i': // Switch to Simulated ram
        ramMapped = false;
        Serial.println("Switched to simulated memory.");
        break;
    }
}

void setFullSpeed(bool full) {
  if (full) {
    fullSpeed = true;
    TClockWidthLow = TClockWidthLowFast;
    TClockWidthHigh = TClockWidthHighFast;
  } else {
    fullSpeed = false;
    TClockWidthLow = TClockWidthLowSlow;
    TClockWidthHigh = TClockWidthHighSlow;
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

void resetCPU() {
  activateReset(true);
  clockHigh();
  delayFor(10);
  clockLow();
  delayFor(10);
  clockHigh();
  delayFor(10);
  clockLow();
  delayFor(10);
  activateReset(false);
  Serial.println("---- CPU Reset ----");
}

void performClockCycle() {
  uint16_t address = readFromAddressBus();

  if (memoryArea(address) == MAP_RAM) {
    // Clock cycle with real memory
    clockHigh();
    delayFor(TClockWidthHigh);
    maybeShowState();
    clockLow();
    delayFor(TClockWidthLow);
  } else {
    selectRamChip(false);
    if (readWriteLineIsRead()) {
      // Read cycle with simulated memory
      clockHigh();
      uint8_t data = getMemory(address);
      configureDataBus(OUTPUT);
      writeToDataBus(data);
      delayFor(TClockWidthHigh);
      maybeShowState();
      clockLow();
      delayFor(THoldRead);
      configureDataBus(INPUT);
      delayFor(TClockWidthLow - THoldRead);
    } else {
      // Write cycle with simulated memory
      clockHigh();
      delayFor(TClockWidthHigh);
      maybeShowState();
      uint8_t data = readFromDataBus();
      putMemory(address, data);
      clockLow();
      delayFor(TClockWidthLow);
    }
    selectRamChip(true);
  }
}

void delayFor(uint32_t duration) {
  if (duration > 10000) {
    delay(duration / 1000);
  } else {
    delayMicroseconds(duration); 
  }
}
