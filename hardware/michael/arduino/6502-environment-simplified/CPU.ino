void performClockCycles() {
  for (uint16_t n = 0; n < POLL_INTERVAL; n++) {
    performClockCycle();
  }

  checkForCharacters();
}

void performManualClockCycle() {
  performClockCycle();
  checkForCharacters();
}

void performClockCycle() {
  clockHigh();
  delayFor(TClockWidthFree);
  clockLow();
  delayFor(TClockWidthFree);
}
