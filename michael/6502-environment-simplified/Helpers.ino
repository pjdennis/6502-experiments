void boot() {
  copyEepromToRam();
  Serial.println("Copied EEPROM to RAM.");
  initializeCharacterBuffer();
  Serial.println("Initialized character buffer.");
  resetCPU();
}

void resetCPU() {
  activateReset(true);
  performClockCycle();
  performClockCycle();
  activateReset(false);
  Serial.println("---- CPU Reset ----");
}

void delayFor(uint32_t duration) {
  if (duration > 10000) {
    delay(duration / 1000);
  } else {
    delayMicroseconds(duration);
  }
}
