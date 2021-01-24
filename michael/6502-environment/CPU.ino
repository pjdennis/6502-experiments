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
