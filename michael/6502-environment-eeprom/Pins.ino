const uint8_t CLOCK      = 23; // White
const uint8_t RD_WRB     = 25; // Brown (joined with bus pins)
const uint8_t RESB       = 27; // Yellow
const uint8_t EEPROM_WEB = 29; // Orange
const uint8_t RDY        = 31; // Green
const uint8_t BE         = 33; // Purple
const uint8_t EEPROM_OEB = 35; // Grey
const uint8_t PROBE      = 37; // Blue
const uint8_t ADDR[]     = {22, 24, 26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48, 50, 52};
const uint8_t DATA[]     = {39, 41, 43, 45, 47, 49, 51, 53};

bool probeIsHigh() {
  return digitalRead(PROBE);
}

void clockLow() {
  digitalWrite(CLOCK, 0);
}

void clockHigh() {
  digitalWrite(CLOCK, 1);
}

void enableCpuBuses(bool enable) {
  digitalWrite(BE, enable ? 1 : 0);
}

void outputEnableEepromChip(bool enable) {
  digitalWrite(EEPROM_OEB, enable ? 0 : 1);
}

void setWriteEeprom(bool write) {
  digitalWrite(EEPROM_WEB, write ? 0 : 1);
}

void setReady(bool ready) {
  digitalWrite(RDY, ready ? 1 : 0);
}

void activateReset(bool reset) {
  pinMode(RESB, reset ? OUTPUT : INPUT);
}

void configureAddressBus(uint8_t mode) {
  for (int n = 0; n < 16; n += 1) {
    pinMode(ADDR[n], mode);
  }
}

void configureDataBus(uint8_t mode) {
  for (int n = 0; n < 8; n += 1) {
    pinMode(DATA[n], mode);
  }
}

void configurePinsSafe() {
  configureAddressBus(INPUT_PULLUP);
  configureDataBus(INPUT_PULLUP);
  pinMode(RD_WRB, INPUT_PULLUP);

  outputEnableEepromChip(false);
  pinMode(EEPROM_OEB, OUTPUT);

  setWriteEeprom(false);
  pinMode(EEPROM_WEB, OUTPUT);

  setReady(false);
  pinMode(RDY, OUTPUT);

  enableCpuBuses(false);
  pinMode(BE, OUTPUT);

  clockLow();
  pinMode(CLOCK, OUTPUT);

  pinMode(RESB, INPUT);
}

void configureForArduinoToEeprom() {
  configurePinsSafe();
  configureAddressBus(OUTPUT);
  outputEnableEepromChip(true);
}

void configureForCpu() {
  configurePinsSafe();
  enableCpuBuses(true);
  configureAddressBus(INPUT);
  configureDataBus(INPUT);
  pinMode(RD_WRB, INPUT);
  outputEnableEepromChip(true);
  setReady(true);
}

uint16_t readFromAddressBus() {
  uint16_t address = 0;
  for (int n = 0; n < 16; n += 1) {
    int bit = digitalRead(ADDR[n]) ? 1 : 0;
    address = (address << 1) + bit;
  }
  return address;
}

uint8_t readFromDataBus() {
  uint16_t data = 0;
  for (int n = 0; n < 8; n += 1) {
    int bit = digitalRead(DATA[n]) ? 1 : 0;
    data = (data << 1) + bit;
  }
  return data;  
}

bool readWriteLineIsRead() {
  return digitalRead(RD_WRB);
}

void writeToAddressBus(uint16_t address) {
  for (int n = 15; n >= 0; n -= 1) {
    int bit = bitRead(address, 15 - n);
    digitalWrite(ADDR[n], bit);
  }
}

void writeToDataBus(uint8_t data) {
  for (int n = 7; n >= 0; n -= 1) {
    int bit = bitRead(data, 7 - n);
    digitalWrite(DATA[n], bit);
  }
}
