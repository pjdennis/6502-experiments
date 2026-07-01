#!/usr/bin/env python3
"""Integration test for 6502 web server running in the emulator."""

import os
import signal
import subprocess
import sys
import time
import urllib.request
import urllib.error

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_DIR = os.path.dirname(SCRIPT_DIR)
EMULATOR = os.path.join(BASE_DIR, "emulator.out")
ASSEMBLER = os.path.join(BASE_DIR, "23", "out", "asm_debug.out")
WEBSERVER_SRC = os.path.join(BASE_DIR, "webserver", "webserver.asm")
WEBSERVER_BIN = os.path.join(BASE_DIR, "webserver", "out", "webserver.out")
PORT = 8080
URL = f"http://localhost:{PORT}"


def build_emulator():
    print("Building emulator...")
    result = subprocess.run(["make", "--quiet"], cwd=BASE_DIR)
    if result.returncode != 0:
        print("FAIL: emulator build failed")
        sys.exit(1)


def assemble_webserver():
    print("Assembling web server...")
    os.makedirs(os.path.dirname(WEBSERVER_BIN), exist_ok=True)
    result = subprocess.run(
        [EMULATOR, ASSEMBLER, WEBSERVER_SRC, WEBSERVER_BIN],
        cwd=BASE_DIR,
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"FAIL: assembly failed\nstderr: {result.stderr}")
        sys.exit(1)
    print("Assembly OK")


def wait_for_port(port, timeout=10):
    start = time.time()
    while time.time() - start < timeout:
        try:
            urllib.request.urlopen(f"http://localhost:{port}", timeout=1)
            return True
        except (urllib.error.URLError, ConnectionRefusedError, OSError):
            time.sleep(0.2)
    return False


def test_webserver():
    print(f"Starting web server on port {PORT}...")
    proc = subprocess.Popen(
        [EMULATOR, WEBSERVER_BIN, "--no-cycle-limit", "--load", "1000"],
        cwd=BASE_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE
    )

    try:
        if not wait_for_port(PORT):
            print("FAIL: web server did not start within timeout")
            stderr = proc.stderr.read().decode(errors='replace')
            if stderr:
                print(f"stderr: {stderr[:500]}")
            return False

        print(f"Requesting {URL}...")
        response = urllib.request.urlopen(URL, timeout=5)
        body = response.read().decode()
        print(f"Response status: {response.status}")
        print(f"Response body ({len(body)} bytes): {body[:200]}...")

        if "Hello from 6502 asm" not in body:
            print("FAIL: response does not contain 'Hello from 6502 asm'")
            return False

        if response.status != 200:
            print(f"FAIL: expected status 200, got {response.status}")
            return False

        print("PASS: web server returned expected content")
        return True

    finally:
        proc.send_signal(signal.SIGTERM)
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


if __name__ == "__main__":
    build_emulator()

    if not os.path.exists(ASSEMBLER):
        print(f"Assembler not found at {ASSEMBLER}")
        print("Run ./asmtestgen.sh first to build the assembler")
        sys.exit(1)

    assemble_webserver()
    success = test_webserver()
    sys.exit(0 if success else 1)
