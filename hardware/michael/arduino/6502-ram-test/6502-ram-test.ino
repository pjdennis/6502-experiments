const uint8_t CLOCK = 23;
const uint8_t RD_WRB = 25;
const uint8_t RESB = 27;
const uint8_t RAM_CSB = 29;
const uint8_t RAM_WEB = 31;
const uint8_t ADDR[] = {22, 24, 26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48, 50, 52};
const uint8_t DATA[] = {39, 41, 43, 45, 47, 49, 51, 53};

void setup() {
  digitalWrite(CLOCK, 1);
  pinMode(CLOCK, OUTPUT);

  pinMode(RD_WRB, INPUT);
  pinMode(RESB, INPUT);

  digitalWrite(RAM_CSB, 1);
  pinMode(RAM_CSB, OUTPUT);

  digitalWrite(RAM_WEB, 1);
  pinMode(RAM_WEB, OUTPUT);

  for (int n = 0; n < 16; n += 1) {
    pinMode(ADDR[n], OUTPUT); // Warning! 6502 bus to be disabled.
  }

  configureDataPins(INPUT);
  
  Serial.begin(115200);

  Serial.println("---- Ardino restarted ----");

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
  configureDataPins(INPUT);
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
}

void delayFor(uint32_t duration) {
  if (duration > 10000) {
    delay(duration / 1000);
  } else {
    delayMicroseconds(duration); 
  }
}

void configureDataPins(uint8_t mode) {
  for (int n = 0; n < 8; n += 1) {
    pinMode(DATA[n], mode);
  }
}

void writeAddress(uint16_t address) {
  for (int n = 15; n >= 0; n -= 1) {
    int bit = bitRead(address, 15 - n);
    digitalWrite(ADDR[n], bit);
  }
}

uint8_t readData() {
  uint16_t data = 0;
  for (int n = 0; n < 8; n += 1) {
    int bit = digitalRead(DATA[n]) ? 1 : 0;
    data = (data << 1) + bit;
  }
  return data;  
}

void writeData(uint8_t data) {
  for (int n = 7; n >= 0; n -= 1) {
    int bit = bitRead(data, 7 - n);
    digitalWrite(DATA[n], bit);
  }
}

/*
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
*/
