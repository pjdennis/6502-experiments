void boot() {
  if (ramMapped) {
    copyEepromToRam();
    Serial.println("Copied EEPROM to RAM.");
  }
  initializeCharacterBuffer();
  Serial.println("Initialized character buffer.");
  resetCPU();
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

void setRunMode(uint8_t mode) {
  runMode = mode;
  if (mode == RUN_MODE_FAST) {
    TClockWidthLow = TClockWidthLowFast;
    TClockWidthHigh = TClockWidthHighFast;
  } else if (mode == RUN_MODE_SLOW) {
    TClockWidthLow = TClockWidthLowSlow;
    TClockWidthHigh = TClockWidthHighSlow;
  }
}

void delayFor(uint32_t duration) {
  if (duration > 10000) {
    delay(duration / 1000);
  } else {
    delayMicroseconds(duration);
  }
}
