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
const uint8_t RAM_CSB = 29;
const uint8_t RAM_WEB = 31;
const uint8_t BE = 33;
const uint8_t ADDR[] = {22, 24, 26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48, 50, 52};
const uint8_t DATA[] = {39, 41, 43, 45, 47, 49, 51, 53};

uint8_t MEMORY[MEMORY_SIZE];

uint8_t ROM_BUFFER[ROM_SIZE];

uint32_t TClockWidthLowSlow   = 125000;
uint32_t TClockWidthHighSlow  = 125000;
uint32_t TClockWidthLowFast   = 2;
uint32_t TClockWidthHighFast  = 2;

uint32_t TClockWidthLow    = 2;
uint32_t TClockWidthHigh   = 2;
const uint32_t THoldRead   = 1;
const uint32_t TSetupWrite = 1;

bool processorRunning = false;
bool fullSpeed;

/*
 * Preconditions:
 * Clock starts high
 * Arduino data pins set to input
 * 
 * Read cycle:
 * Arduino: Clock high->low
 * 6502:    T address setup passes
 * 6502:    Valid address for reading asserted; read asserted
 * Arduino: Wait for T clock (pulse width low)
 * Arduino: Clock low->high
 * 6502:    Nothing new happening
 * Arduino: Outputs data for address onto data bus
 * Arduino: Wait for T clock (pulse width high)
 * Arduino: Clock high->low                          <- start of next cycle
 * 6502:    reads in data
 * Arduino: Wait for T hold read
 * Arduino: set data pins to input
 * 
 * Write cycle:
 * Arduino: Clock high->low
 * 6502:    T address setup passes
 * 6502:    Valid address for writing asserted; write asserted
 * Arduino: Wait for T clock (pulse width low)
 * Arduino: Clock low->high
 * 6502:    T write data setup passes
 * 6502:    Outputs data for writing
 * Arduino: Wait for T write data setup
 * Arduino: Read in data for address
 * Arduino: Wait for balance of T clock (pulse width high)
 * Arduino: Clock high->low                          <- start of next cycle
 * 6502:    T hold write passes
 * 6502:    Disconnect from data bus
 * 
 * Combined algorithm:
 * 
 * Arduino: Forever:
 * Arduino:   Clock high->low
 * Arduino:   Wait for T hold read
 * Arduino:   Set data bus to input
 * Arduino:   Wait for balance of T clock (pulse width low)
 * Arduino:   Clock low->high
 * Arduino:   Read address and RD_WRB flag
 * Arduino:   If read:
 * Arduino:     Set data bus to output
 * Arduino:     Output data for address onto data bus
 * Arduino:     Wait for T clock (pulse width high)
 * Arduino:   Else (write):
 * Arduino:     Wait for T write data setup
 * Arduino:     Read in data for address
 * Arduino:     Wait for balance of T clock (pulse width high)
 * 
 */

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
  digitalWrite(RAM_CSB, select ? 0 : 1);
}

void setRamWrite(bool write) {
  digitalWrite(RAM_WEB, write ? 0 : 1);
}

void configureSafe() {
  pinMode(RAM_CSB, INPUT_PULLUP);
  pinMode(RAM_WEB, INPUT_PULLUP);
  configureAddressPins(INPUT_PULLUP);
  configureDataPins(INPUT_PULLUP);
  pinMode(RD_WRB, INPUT_PULLUP);
  enableCpuBus(false);
  clockHigh();
  pinMode(CLOCK, OUTPUT);
  pinMode(RESB, INPUT);
}

void configureForArduinoToRam() {
  configureSafe();

  configureAddressPins(OUTPUT);

  pinMode(RAM_CSB, OUTPUT); // value HIGH from INPUT_PULLUP in configureSafe()
  pinMode(RAM_WEB, OUTPUT); // value HIGH from INPUT_PULLUP in configureSafe()
}

void configureForCpu() {
  configureSafe();
  enableCpuBus(true);
  configureAddressPins(INPUT);
  configureDataPins(INPUT);
  pinMode(RD_WRB, INPUT);
  pinMode(RAM_CSB, OUTPUT);
  pinMode(RAM_WEB, OUTPUT);  
}

void setup() {
  configureForArduinoToRam();
  
  Serial.begin(115200);
  Serial.println("---- Ardino restarted ----");

  testRam();

  configureForCpu();

  initializeData();

  setFullSpeed(false);

  resetCPU();
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
  digitalWrite(RAM_WEB, 0);
  digitalWrite(RAM_CSB, 0);
  delayFor(1);
  digitalWrite(RAM_CSB, 1);
  digitalWrite(RAM_WEB, 1);
  configureDataPins(INPUT_PULLUP);
}

uint8_t readFromRam(uint16_t address) {
  writeAddress(address);
  digitalWrite(RAM_CSB, 0);
  delayFor(1);
  uint8_t data = readData();
  digitalWrite(RAM_CSB, 1);
  return data;
}

void showHex(uint8_t x) {
  char buffer[3];
  sprintf(buffer, "%02x", x);
  Serial.println(buffer);
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
      case 'f':
        setFullSpeed(true);
        Serial.println("Full speed selected.");
        break;
      case 'w':
        setFullSpeed(false);
        Serial.println("Slow speed selected.");
        break;
      case 's':
        processorRunning = false;
        Serial.println("Processor stopped.");
        break;
      case 'g':
        processorRunning = true;
        Serial.println("Processor started.");
        break;
      case 'c':
        performClockCycle();
        break;
      case 'r':
        resetCPU();
        break;
      case 'b':
        initializeData();
        resetCPU();
        break;
      case 'v':
        Serial.println("---- Version 4 ----");
        break;
      case 'l':
        loadMemoryFromSerial();
        break;
      case 'd':
        dumpMemory(MEMORY_START, MEMORY_SIZE);
        break;
      case 'm':
        dumpMemory(ROM_START, ROM_SIZE);
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
    putRom(ROM_START + n, ROM_BUFFER[n]);
  }
  Serial.println("Data loaded.");
}

void resetCPU() {
  pinMode(RESB, OUTPUT); // Default level is LOW
  digitalWrite(CLOCK, 0);
  delayFor(10);
  digitalWrite(CLOCK, 1);
  delayFor(10);
  digitalWrite(CLOCK, 0);
  delayFor(10);
  digitalWrite(CLOCK, 1);
  delayFor(10);
  pinMode(RESB, INPUT);
  Serial.println("---- CPU Reset ----");
}

void performClockCycle() {
  digitalWrite(CLOCK, LOW);
  delayFor(THoldRead);

  // Disable possible outputs from prior cycle
  configureDataPins(INPUT);
  selectRamChip(false);

  delayFor(TClockWidthLow - THoldRead);
  
  digitalWrite(CLOCK, HIGH);
  
  uint16_t address = readAddress();
  bool rd_wrb = digitalRead(RD_WRB);

  if (memoryArea(address) == MAP_RAM) {
    if (rd_wrb) {
      selectRamChip(true);
      delayFor(TClockWidthHigh);      
      uint8_t data = readData();
      showState(address, data, 'r', 'R');
    } else {
      setRamWrite(true);
      selectRamChip(true);
      delayFor(TClockWidthHigh);
      uint8_t data = readData();
      selectRamChip(false);
      setRamWrite(false);
      showState(address, data, 'w', 'R');
    }
  } else {
    if (rd_wrb) {
      configureDataPins(OUTPUT);
      uint8_t data = getMemory(address);
      writeData(data);
      delayFor(TClockWidthHigh);
      showState(address, data, 'r', 'S');
    } else {
      delayFor(TSetupWrite);
      uint8_t data = readData();
      putMemory(address, data);
      delayFor(TClockWidthHigh - TSetupWrite);
      showState(address, data, 'W', 'S');    
    }
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
  if (address >= MEMORY_START && address - MEMORY_START < MEMORY_SIZE) return MAP_SIMULATED_RAM;
  if (address >= ROM_START && address - ROM_START < ROM_SIZE) return MAP_SIMULATED_EEPROM;
  if (address >= IO_START && address - IO_START < IO_SIZE) return MAP_SIMULATED_IO;
  return MAP_RAM;
}

uint8_t getMemory(uint16_t address) {
  uint8_t area = memoryArea(address);
  if (area == MAP_SIMULATED_RAM) {
    return MEMORY[address];
  } else if (area == MAP_SIMULATED_EEPROM) {
    return EEPROM[address - ROM_START];
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

void putIo(uint16_t address, uint8_t data) {
  if (address = COUT_PORT) {
    characterOut(data);
  }
}

void putRom(uint16_t address, uint8_t data) {
  if (memoryArea(address) == MAP_SIMULATED_EEPROM) {
    EEPROM[address - (0x10000 - ROM_SIZE)] = data;
  }
}

void characterOut(uint8_t data) {
  char dataChar = (char) data;
  if (fullSpeed && processorRunning) {
    Serial.write(dataChar);
  } else {
    char buffer[7];
    Serial.write("CPU wrote the value: ");
    sprintf(buffer, "%c (%02x)", isPrintable(dataChar) ? dataChar : '.', data);
    Serial.println(buffer);
  }
}

void showState(uint16_t address, uint8_t data, char operation, char area) {
  if (fullSpeed && processorRunning) return;

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

const uint8_t NOP    = 0xEA;
const uint8_t TAX    = 0xAA;
const uint8_t LDX_ZP = 0xA6;
const uint8_t STX_ZP = 0x86;
const uint8_t INX    = 0xE8;
const uint8_t JMP    = 0x4C;

const uint8_t N_ADDR = 0x1F;

void initializeData() {
  uint16_t address = 0;
  putMemory(address++, LDX_ZP); putMemory(address++, N_ADDR); // LDX N_ADDR
  putMemory(address++, INX);                                  // INX
  putMemory(address++, STX_ZP); putMemory(address++, N_ADDR); // STX N_ADDR
  putMemory(address++, JMP); putMemory(address++, 0); putMemory(address++, 0); //JMP 0

  while (address < MEMORY_SIZE) {
    putMemory(address++, 0);
  }
  
  Serial.println("---- Memory initialized ----");
}
