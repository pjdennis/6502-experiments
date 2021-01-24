void handleSerialCommand() {
    int c = Serial.read();
    switch (c) {
      case 'f': // Set Full speed
        setFullSpeed(true);
        Serial.println("Full speed selected.");
        break;
      case 'w': // Set sloW speed
        setFullSpeed(false);
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
      case 'a': // Switch to real rAm
        configureForArduinoToRam();
        copyEepromToRam();
        configureForCpu();
        ramMapped = true;
        Serial.println("Switched to real memory and copied ROM over.");
        break;
      case 'i': // Switch to Simulated ram
        ramMapped = false;
        Serial.println("Switched to simulated memory.");
        break;
    }
}
