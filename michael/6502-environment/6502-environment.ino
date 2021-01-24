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

const uint8_t CLOCK = 23;
const uint8_t RD_WRB = 25;
const uint8_t RESB = 27;
const uint8_t RAM_CK_GATED_CS = 29;
const uint8_t RDY = 31;
const uint8_t BE = 33;
const uint8_t ADDR[] = {22, 24, 26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48, 50, 52};
const uint8_t DATA[] = {39, 41, 43, 45, 47, 49, 51, 53};

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

void clockLow() {
  digitalWrite(CLOCK, 0);
}

void clockHigh() {
  digitalWrite(CLOCK, 1);
}

void enableCpuBus(bool enable) {
  digitalWrite(BE, enable ? 1 : 0);
}

void selectRamChip(bool select) {
  digitalWrite(RAM_CK_GATED_CS, select ? 1 : 0);
}

void setWrite(bool write) {
  digitalWrite(RD_WRB, write ? 0 : 1);
}

void setReady(bool ready) {
  digitalWrite(RDY, ready ? 1 : 0);
}

void configureSafe() {
  selectRamChip(false);
  pinMode(RAM_CK_GATED_CS, OUTPUT);

  configureAddressPins(INPUT_PULLUP);
  configureDataPins(INPUT_PULLUP);
  pinMode(RD_WRB, INPUT_PULLUP);

  setReady(false);
  pinMode(RDY, OUTPUT);

  enableCpuBus(false);

  clockLow();
  pinMode(CLOCK, OUTPUT);

  pinMode(RESB, INPUT);
}

void configureForArduinoToRam() {
  configureSafe();
  configureAddressPins(OUTPUT);
  pinMode(RD_WRB, OUTPUT); // Set to read via HIGH from INPUT_PULLUP in configureSafe()
  clockHigh(); // Allow chip to be selected
}

void configureForCpu() {
  configureSafe();
  enableCpuBus(true);
  configureAddressPins(INPUT);
  configureDataPins(INPUT);
  pinMode(RD_WRB, INPUT);
  selectRamChip(true);
  setReady(true);
}

void testRam() {
  writeToRam(0x0000, 0x55);
  writeToRam(0x0001, 0x88);
  showHex(readFromRam(0x0000));
  writeToRam(0x0000, 0x42);
  showHex(readFromRam(0x0001));
  showHex(readFromRam(0x0000));
}

void writeToRam(uint16_t address, uint8_t data) {
  writeAddress(address);
  configureDataPins(OUTPUT);
  writeData(data);
  setWrite(true);
  selectRamChip(true);
  delayFor(1);
  selectRamChip(false);
  setWrite(false);
  configureDataPins(INPUT_PULLUP);
}

uint8_t readFromRam(uint16_t address) {
  writeAddress(address);
  selectRamChip(true);
  delayFor(1);
  uint8_t data = readData();
  selectRamChip(false);
  return data;
}

void showHex(uint8_t x) {
  char buffer[3];
  sprintf(buffer, "%02x", x);
  Serial.println(buffer);
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
  pinMode(RESB, OUTPUT); // Default level is LOW
  clockHigh();
  delayFor(10);
  clockLow();
  delayFor(10);
  clockHigh();
  delayFor(10);
  clockLow();
  delayFor(10);
  pinMode(RESB, INPUT);
  Serial.println("---- CPU Reset ----");
}

void performClockCycle() {
  uint16_t address = readAddress();

  if (memoryArea(address) == MAP_RAM) {
    // Clock cycle with real memory
    clockHigh();
    delayFor(TClockWidthHigh);
    maybeShowState();
    clockLow();
    delayFor(TClockWidthLow);
  } else {
    bool rd_wrb = digitalRead(RD_WRB);
    selectRamChip(false);
    if (rd_wrb) {
      // Read cycle with simulated memory
      clockHigh();
      uint8_t data = getMemory(address);
      configureDataPins(OUTPUT);
      writeData(data);
      delayFor(TClockWidthHigh);
      maybeShowState();
      clockLow();
      delayFor(THoldRead);
      configureDataPins(INPUT);
      delayFor(TClockWidthLow - THoldRead);
    } else {
      // Write cycle with simulated memory
      clockHigh();
      delayFor(TClockWidthHigh);
      maybeShowState();
      uint8_t data = readData();
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

void configureAddressPins(uint8_t mode) {
  for (int n = 0; n < 16; n += 1) {
    pinMode(ADDR[n], mode);
  }
}

void configureDataPins(uint8_t mode) {
  for (int n = 0; n < 8; n += 1) {
    pinMode(DATA[n], mode);
  }
}

uint16_t readAddress() {
  uint16_t address = 0;
  for (int n = 0; n < 16; n += 1) {
    int bit = digitalRead(ADDR[n]) ? 1 : 0;
    address = (address << 1) + bit;
  }
  return address;
}

uint8_t readData() {
  uint16_t data = 0;
  for (int n = 0; n < 8; n += 1) {
    int bit = digitalRead(DATA[n]) ? 1 : 0;
    data = (data << 1) + bit;
  }
  return data;  
}

void writeAddress(uint16_t address) {
  for (int n = 15; n >= 0; n -= 1) {
    int bit = bitRead(address, 15 - n);
    digitalWrite(ADDR[n], bit);
  }
}

void writeData(uint8_t data) {
  for (int n = 7; n >= 0; n -= 1) {
    int bit = bitRead(data, 7 - n);
    digitalWrite(DATA[n], bit);
  }
}

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

void maybeShowState() {
  if (shouldShowState()) {
      uint16_t address = readAddress();
      uint8_t data = readData();
      bool rd_wrb = digitalRead(RD_WRB);
      uint8_t area = memoryArea(address);

      showState(address, data, rd_wrb ? 'r' : 'W', area == MAP_RAM ? 'R' : 'S');
  }
}

bool shouldShowState() {
  return !fullSpeed || !processorRunning;
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

  char output[22];
  sprintf(output, "   %04x %c  %c %02x .. %c",
    address,
    isPrintable(dataChar) ? dataChar : ' ',
    operation,
    data,
    area);

  Serial.print(output);

  Serial.println();
}
