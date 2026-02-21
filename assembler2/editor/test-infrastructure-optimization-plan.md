# Editor Test Infrastructure Optimization Plan

## Goal

Reduce the editor test suite runtime (~5.1s for 1070 tests) by eliminating
per-test overhead: subprocess creation, redundant emulator initialization,
and temp file I/O.

## Current Measurements (WSL2 Ubuntu)

| Component                  | Time      | % of Total |
|----------------------------|-----------|------------|
| Build 3 editor variants    | 1,434ms   | 22%        |
| Subprocess calls (1,073)   | 3,736ms   | 58%        |
| Python overhead            | 1,234ms   | 20%        |
| **Total**                  | **~5.1s** |            |

Per-test averages (minimal quit test):
- subprocess.run overhead (fork/exec/wait): ~1.0ms
- Emulator init (memory zero, binary load, stub gen): ~0.6ms
- 6502 emulation: ~0.2ms (29K cycles for quit)
- Temp dir + file I/O: ~0.8ms

## Three Optimizations

### Phase 1: Persistent Emulator Process

**Estimated savings: ~1.0-1.5s**

Add a `--server` mode to the emulator. Instead of one process per test,
a single emulator process stays alive and accepts test commands via stdin.

#### Emulator changes (`emulator.c`)

Add a `--server` flag. When active, after initial argument parsing the
emulator enters a command loop reading newline-terminated commands from
a control file descriptor (fd 3, opened via `--server-fd 3` or similar).

Protocol (text-based, one command per line):

```
BINARY <path>           # Load a new 6502 binary (if different from current)
LOAD <hex-address>      # Set load address (e.g., 0400)
ROWS <n>                # Terminal rows
COLS <n>                # Terminal cols
MODE standard|terminal  # Selects I/O stub variant
INPUT <path>            # Keystroke input file
OUTPUT <path>           # ANSI output file
ARG <string>            # Add a program argument (repeatable)
RUN                     # Reset state, execute, return result
```

When BINARY is received, the emulator loads the binary, generates I/O
stubs, and saves a pristine snapshot of the entire 64KB memory space:
`memcpy(pristine_memory, memory, 0x10001)`. This snapshot captures the
loaded code, I/O stubs at $F006+, and zeroed RAM — the exact state
before any 6502 execution.

On receiving `RUN`:
1. Restore entire memory from pristine snapshot:
   `memcpy(memory, pristine_memory, 0x10001)`
2. Rewrite program arguments into high memory (after stubs)
3. Reopen input/output files from specified paths
4. `reset6502()`, clear `done`/`exitcode_set`/cycle counters
5. Call `files_init()`, reset serial buffers
6. Execute the main emulation loop
7. Write result to fd 3: `EXIT <code>\n`
8. Close input/output files, call `files_destroy()`
9. Return to command loop

Restoring the full 64KB every run (rather than selectively zeroing RAM
and preserving code) ensures that if a test corrupts program memory or
I/O stubs during execution, the next test still starts from a known-good
state. A single `memcpy` of 64KB is fast (~10us on modern hardware) and
simpler than tracking which regions to preserve vs. clear.

#### Python changes (`editor_tests.py`)

Add a `PersistentEmulator` class wrapping `subprocess.Popen`:

```python
class PersistentEmulator:
    def __init__(self, emulator_path):
        self.proc = subprocess.Popen(
            [str(emulator_path), '--server'],
            stdin=subprocess.PIPE,    # for control commands
            stdout=subprocess.PIPE,   # for results
            stderr=subprocess.PIPE
        )
        self.current_binary = None

    def run_test(self, binary, load_addr, input_file, output_file,
                 args, rows=0, cols=0, mode='standard'):
        # Send BINARY only when it changes
        if binary != self.current_binary:
            self._send(f'BINARY {binary}')
            self.current_binary = binary
        self._send(f'LOAD {load_addr:04x}')
        if rows: self._send(f'ROWS {rows}')
        if cols: self._send(f'COLS {cols}')
        self._send(f'MODE {mode}')
        self._send(f'INPUT {input_file}')
        self._send(f'OUTPUT {output_file}')
        for arg in args:
            self._send(f'ARG {arg}')
        self._send('RUN')
        return self._read_result()  # Reads "EXIT <code>\n"

    def close(self):
        self._send('QUIT')
        self.proc.wait(timeout=5)
```

The existing `run_editor`, `run_editor_screen`, `run_editor_terminal`,
etc. methods are updated to call `self.emulator_proc.run_test(...)` instead
of `subprocess.run(...)`. Temp files for keys and output are still used
in this phase.

#### Implementation steps (TDD)

1. **Refactor**: Extract emulator invocation in `editor_tests.py` into a
   helper class (`EmulatorRunner`) that encapsulates the current
   subprocess.run pattern. All existing `run_editor*` methods call through
   it. Verify all 1070 tests pass. Commit.

2. **Add `--server` mode skeleton to emulator.c**: Parse `--server` flag,
   enter a command loop that reads commands and responds with
   `EXIT 0\n` without actually running anything. Add a simple Python
   integration test that starts the server, sends a QUIT command, and
   verifies clean exit. Commit.

3. **Implement BINARY/LOAD/RUN commands**: BINARY loads the binary,
   generates stubs, and saves the pristine 64KB memory snapshot. RUN
   restores from the snapshot, resets CPU state, opens files, runs
   emulation, and returns exit code. Write a test that sends a minimal
   editor test (quit immediately) via the server protocol and verifies
   the exit code and output file match the subprocess.run result. Commit.

4. **Implement remaining commands** (ROWS/COLS/MODE/ARG): Add terminal
   size, mode switching, and argument passing. Write tests for terminal
   mode and screen-size variants. Commit.

5. **Add `PersistentEmulator` class** to `editor_tests.py` implementing
   the `EmulatorRunner` interface. Wire it up so all tests run through
   the persistent process. Verify all 1070 tests pass. Commit.

6. **Benchmark**: Measure and record the improvement.

### Phase 2: Skip Redundant Binary Reload

**Estimated savings: ~0.2-0.3s additional**

When the same binary is requested for consecutive tests (which is the
common case), avoid reloading it from disk and regenerating I/O stubs.
The pristine snapshot from Phase 1 is already correct — just skip the
work that produced it.

#### Emulator changes

Track the current binary path and MODE. When BINARY receives the same
path and MODE hasn't changed:
- Skip `fopen`/`fread` of the binary file
- Skip I/O stub generation
- Keep the existing pristine snapshot (it's already correct)

When BINARY changes or MODE changes (the serial_write stub differs
between standard and terminal mode): reload from disk, regenerate stubs,
and update the pristine snapshot.

#### Python changes

Minimal. The `PersistentEmulator` class already sends BINARY only when
it changes. Ensure tests are ordered to minimize binary switches (they
already are: standard tests first, then small-buffer, then terminal).

#### Implementation steps (TDD)

1. **Skip reload for same binary**: Track current binary path and mode.
   When BINARY receives the same path, skip file I/O and stub gen.
   Verify all tests pass. Commit.

2. **Handle MODE changes**: When MODE changes, regenerate stubs and
   update the pristine snapshot (even if binary path is unchanged).
   Commit.

3. **Benchmark**: Measure the additional improvement.

### Phase 3: Replace Temp Files with Pipes

**Estimated savings: ~0.4s additional**

Eliminate the per-test overhead of creating temp directories and writing
keys.bin / reading output.txt files.

#### Protocol extensions

Add two new commands for sending/receiving binary data inline:

```
KEYS <length>\n<length bytes of keystroke data>
```

Instead of INPUT pointing to a keys file, the keystroke data is sent
directly through the control channel. The emulator buffers it in memory
and feeds it to the 6502 program via the read_b port.

```
INLINE_OUTPUT\n
```

Instead of OUTPUT pointing to a file, the emulator buffers ANSI output
in memory and sends it back after RUN completes:

```
EXIT <code>
OUTPUT <length>\n<length bytes of ANSI output>
DONE
```

The edit file itself (the file the editor opens, modifies, and saves)
still lives on the filesystem because the 6502 editor accesses it
through the emulator's file I/O ports ($F012 open, $F018 read, etc.).
However, we can reuse a single temp directory across all tests instead
of creating/destroying one per test.

#### Emulator changes

- Add a `keys_buffer` (dynamically allocated, max ~64KB) to store
  keystroke data received via the KEYS command
- When `read_b` port is accessed, read from `keys_buffer` instead of
  `input_file_ptr` (when in server mode with KEYS provided)
- Add an `output_buffer` (dynamically allocated, grows as needed) to
  capture bytes written to the `write_b` port
- After RUN completes, write `OUTPUT <length>\n` + buffer contents to
  the control channel
- For terminal mode: similar buffering for serial_write output

#### Python changes

- `PersistentEmulator.run_test()` sends keystroke bytes via KEYS command
  instead of writing keys.bin
- Reads ANSI output from the result message instead of output.txt
- `run_editor*` methods no longer create keys_file or output_file
- Use a single shared temp directory (created once per test suite) for
  the edit file, reusing the same path each test

```python
def run_test(self, binary, load_addr, keys, args, rows=0, cols=0,
             mode='standard'):
    if binary != self.current_binary:
        self._send(f'BINARY {binary}')
        self.current_binary = binary
    self._send(f'LOAD {load_addr:04x}')
    # ... rows/cols/mode/args ...
    self._send(f'KEYS {len(keys)}')
    self._send_raw(keys)
    self._send('INLINE_OUTPUT')
    self._send('RUN')
    exit_code = self._read_exit_code()
    output = self._read_output()     # reads OUTPUT <len>\n + data
    return exit_code, output
```

#### Implementation steps (TDD)

1. **Reuse temp directory**: Change test methods to use a single shared
   tmpdir (created in `__init__` or `run_all_tests`). Verify all tests
   pass with the existing subprocess approach first. Commit.

2. **Add KEYS command to emulator**: Buffer keystroke data in memory,
   use it as the input source during RUN. Write a test that sends
   keystrokes inline and verifies the editor processes them identically
   to file-based input. Commit.

3. **Add INLINE_OUTPUT to emulator**: Buffer output data, send it back
   after RUN completes. Write a test verifying output matches file-based
   output byte-for-byte. Commit.

4. **Wire up Python side**: Update `PersistentEmulator` to use KEYS and
   INLINE_OUTPUT. Remove keys file and output file creation from
   `run_editor*` methods. Verify all 1070 tests pass. Commit.

5. **Benchmark**: Measure the final improvement.

## Expected Results

| State                      | Estimated Time | Improvement |
|----------------------------|----------------|-------------|
| Current                    | ~5.1s          | baseline    |
| After Phase 1 (persistent) | ~3.8-4.1s     | ~1.0-1.3s   |
| After Phase 2 (caching)   | ~3.5-3.8s      | ~0.3s more  |
| After Phase 3 (pipes)     | ~3.1-3.4s      | ~0.4s more  |

Build time (1.4s) is unchanged since it's a one-time cost per suite run.

## Risks and Considerations

- **Deadlocks**: The pipe-based protocol must avoid blocking. The control
  channel (fd 3) is separate from stdin/stdout to prevent interference
  with the 6502 program's I/O. Use non-blocking reads or explicit
  length-prefixed messages to avoid deadlock on large outputs.

- **Emulator state leaks**: Incomplete reset between tests could cause
  flaky failures. The pristine memory snapshot (restored every RUN in
  Phase 1) mitigates this by guaranteeing identical initial memory state,
  including protection against program memory corruption during a run.

- **Timeout handling**: Currently `subprocess.run(timeout=10)` kills hung
  tests. With a persistent process, the Python side needs a timer that
  sends a cancel/reset signal if a test takes too long, rather than
  killing the entire process.

- **Error isolation**: A segfault or infinite loop in the emulator would
  previously affect only one test. With a persistent process, it kills
  the entire suite. The Python wrapper should detect unexpected process
  death and either restart or fail gracefully.

- **Backward compatibility**: Keep the existing one-shot mode working.
  `--server` is opt-in. The test runner should have a `--no-server`
  fallback flag for debugging individual tests.

- **Debugging**: When a test fails, it's useful to reproduce it in
  isolation. Keep the ability to run a single test via the old
  subprocess.run path (e.g., `--no-server` or running the emulator
  manually with the same arguments).
