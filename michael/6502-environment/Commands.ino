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
      case 'e': // Switch to frEe run mode
        if (ramMapped) {
          setRunMode(RUN_MODE_FREE);
          Serial.println("Free run mode selected.");
        } else  {
          Serial.println("Error: ram must be mapped to enter free run mode.");
        }
        break;
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
      case 'a': // Switch to real rAm
        ramMapped = true;
        copyEepromToRam();
        Serial.println("Switched to real memory and copied ROM and MEMORY over.");
        break;
      case 'b': // Perform Boot
        boot();
        break;
      case 'i': // Switch to Simulated ram
        if (runMode == RUN_MODE_FREE) {
          Serial.println("Error: must not be in free run mode to switch to simulated memory.");
        } else {
          ramMapped = false;
          Serial.println("Switched to simulated memory.");
        }
        break;
    }
}
