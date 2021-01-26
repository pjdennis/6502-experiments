/*
 * Base state for RAM:
 *   Clock: low
 *   Clock gated select line: high
 *   Read/not write: read
 *   Address bus: output
 *   Data bus: input pullup
 *   
 * Changes while in read loop:
 *   Clock: high
 *   Data bus: input
 *   
 * Changes while in write loop:
 *   Read/not write: write
 *   Data bus: output
 */

void readRamStart() {
  configureDataBus(INPUT);
  clockHigh();
}

uint8_t readRamStep(uint16_t address) {
  writeToAddressBus(address);
  delayFor(1);
  return readFromDataBus();
}

void readRamStop() {
  clockLow();
  configureDataBus(INPUT_PULLUP);
}

void writeRamStart() {
  setWrite(true); // Assumes clock is low
  configureDataBus(OUTPUT);
}

void switchReadToWriteRam() {
  clockLow();
  setWrite(true);
  configureDataBus(OUTPUT);
}

void writeRamStep(uint16_t address, uint8_t data) {
  writeToAddressBus(address);
  writeToDataBus(data);
  clockHigh();
  delayFor(1);
  clockLow();
}

void writeRamStop() {
  configureDataBus(INPUT_PULLUP);
  setWrite(false);
}
