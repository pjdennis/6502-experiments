const uint8_t CLOCK           = 23;
const uint8_t RD_WRB          = 25;
const uint8_t RESB            = 27;
const uint8_t RAM_CK_GATED_CS = 29;
const uint8_t RDY             = 31;
const uint8_t BE              = 33;
const uint8_t ADDR[]          = {22, 24, 26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48, 50, 52};
const uint8_t DATA[]          = {39, 41, 43, 45, 47, 49, 51, 53};

void clockLow() {
  digitalWrite(CLOCK, 0);
}

void clockHigh() {
  digitalWrite(CLOCK, 1);
}

void enableCpuBuses(bool enable) {
  digitalWrite(BE, enable ? 1 : 0);
}

void selectRamChip(bool select) {
  digitalWrite(RAM_CK_GATED_CS, select ? 1 : 0);
}

void setReady(bool ready) {
  digitalWrite(RDY, ready ? 1 : 0);
}

void activateReset(bool reset) {
  pinMode(RESB, reset ? OUTPUT : INPUT);
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

void setWrite(bool write) {
  digitalWrite(RD_WRB, write ? 0 : 1);
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

void initializePins() {
  setReady(false);
  pinMode(RDY, OUTPUT);

  clockLow();
  pinMode(CLOCK, OUTPUT);

  enableCpuBuses(false);
  pinMode(BE, OUTPUT);

  selectRamChip(false);
  pinMode(RAM_CK_GATED_CS, OUTPUT);

  pinMode(RD_WRB, INPUT_PULLUP);
  configureAddressBus(INPUT_PULLUP);
  configureDataBus(INPUT_PULLUP);
  // End: RDY OUT L; CLOCK OUT L; BE OUT L; RWB IN H; Addr IN H; Data IN H
}

void switchInitialToCpu() {
  // Start: RDY OUT L; CLOCK OUT L; BE OUT L; RWB IN H; Addr IN H; Data IN H
  selectRamChip(true);

  enableCpuBuses(true);
  setWrite(true); // turn off pullup
  writeToAddressBus(0x0000); // turn off pullups
  writeToDataBus(0x00); // turn off pullups  
  setReady(true);
  // End: RDY OUT H; CLOCK OUT L; BE OUT H; RWB IN L; Addr IN L; Data IN L
}

void switchCpuToRam() {
  // Start: RDY OUT H; CLOCK OUT L; BE OUT H; RWB IN L; Addr IN L; Data IN L
  setReady(false);
  setWrite(false); // turn on pullup
  enableCpuBuses(false);
  pinMode(RD_WRB, OUTPUT);
  configureAddressBus(OUTPUT);
  configureDataBus(INPUT_PULLUP); // Prevent data bus floating until driven by read/write
  // End: RDY OUT L; CLOCK OUT L; BE OUT L; RWB OUT H; Addr OUT L; Data IN H
}

void switchRamToCpu() {
  // Start RDY OUT No L; CLOCK OUT L; BE OUT L; RWB OUT H; Addr OUT X; Data IN H
  pinMode(RD_WRB, INPUT_PULLUP); // Hold high (read) until CPU bus has taken over
  configureAddressBus(INPUT_PULLUP);
  // Data bus is assumed already to be INPUT_PULLUP

  enableCpuBuses(true);
  setWrite(true); // turn off pullup
  writeToAddressBus(0x0000); // turn off pullups
  writeToDataBus(0x00); // turn off pullups
  setReady(true);
  // End: RDY OUT Yes H; CLOCK OUT L; BE OUT H; RWB IN L; Addr IN L; Data IN L
}
