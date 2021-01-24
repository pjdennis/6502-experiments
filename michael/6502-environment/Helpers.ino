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

void delayFor(uint32_t duration) {
  if (duration > 10000) {
    delay(duration / 1000);
  } else {
    delayMicroseconds(duration);
  }
}
