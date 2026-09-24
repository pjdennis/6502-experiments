void handleSerialCommand() {
    int c = Serial.read();
    switch (c) {
      case 's': // Make processor Stop
        checkForCharacters();
        processorRunning = false;
        Serial.println("Processor stopped.");
        break;
      case 'g': // Make processor Go
        processorRunning = true;
        Serial.println("Processor started.");
        break;
      case 'c': // Perform a clock Cycle
        performManualClockCycle();
        break;
      case 'r': // Perform CPU Reset
        resetCPU();
        break;
      case 'l': // Perform Load of memory from serial
        loadMemoryFromSerial();
        break;
      case 'd': // Perform memory Dump from start of memory
        dumpMemoryLow();
        break;
      case 'm': // Perform memory dump from roM area
        dumpMemoryHigh();
        break;
      case 'b': // Perform Boot
        boot();
        break;
    }
}
