void handleSerialCommand() {
    int c = Serial.read();
    switch (c) {
      case 'f': // Set Fast speed
        setRunMode(RUN_MODE_FAST);
        Serial.println("Full speed selected.");
        break;
      case 'w': // Set sloW speed
        setRunMode(RUN_MODE_SLOW);
        Serial.println("Slow speed selected.");
        break;
      case 's': // Make processor Stop
        processorRunning = false;
        Serial.println("Processor stopped.");
        break;
      case 'g': // Make processor Go
        processorRunning = true;
        Serial.println("Processor started.");
        break;
      case 'c': // Perform a clock Cycle
        performClockCycle();
        break;
      case 'r': // Perform CPU Reset
        resetCPU();
        break;
      case 'l': // Perform Load of memory from serial
        loadMemoryFromSerial();
        break;
      case 'd': // Perform memory Dump from start of memory
        dumpMemory(MEMORY_START, MEMORY_SIZE);
        break;
      case 'm': // Perform memory dump from roM area
        dumpMemory(ROM_START, ROM_SIZE);
        break;
      case 'p': // Copy Arduino EEPROM to 6502 EEPROM
        copyArduinoEepromToEeprom();
        Serial.println("Copied Ardino EEPROM to 6502 EEPROM.");
        break;
      case 'e': // Switch to real Eeprom
        eepromMapped = true;
        Serial.println("Switched to real EEPROM.");
        break;
      case 'b': // Perform Boot
        boot();
        break;
      case 'i': // Switch to Simulated eeprom
        eepromMapped = false;
        Serial.println("Switched to simulated memory.");
        break;
    }
}
