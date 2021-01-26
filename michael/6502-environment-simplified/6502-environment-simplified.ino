const uint32_t TClockWidthFree = 0;
const uint16_t POLL_INTERVAL   = 1000;

bool processorRunning = false;

void setup() {
  initializePins();

  Serial.begin(115200);
  Serial.println("---- Ardino restarted ----");

  switchInitialToCpu();
  boot();
}

void loop() {
  if (Serial.available()) {
    handleSerialCommand();
  } else if (processorRunning) {
    performClockCycles();
  }
}
