// wendy2c web UI: state via WS JSON, audio via WS binary, LCD as
// per-pixel canvas render. Glyphs come from the HD44780 ROM Code A00
// font (extracted from the datasheet — see hd44780_a00_font.js).
// CGRAM patterns ride along in each state snapshot. In 5x10 mode the
// LCD reports f5x10:1 and we render 10-row glyphs with the cursor on
// row 10; CGRAM slots 0..3 each cover 11 bytes (10 dot rows + cursor).

(() => {
  const $ = (id) => document.getElementById(id);

  // ===== HD44780 A00 font (loaded from hd44780_a00_font.js) =====
  const FONT5X8 = window.HD44780_A00.font5x8;     // 256*8 bytes
  const FONT5X10 = window.HD44780_A00.font5x10;   // 32*10 bytes

  function rom5x8(code) {
    // 8 bytes; each byte's low 5 bits are the dot row (bit 4 = leftmost).
    const off = (code & 0xFF) * 8;
    return FONT5X8.subarray(off, off + 8);
  }
  function rom5x10(code) {
    // Defined only for codes 0xE0..0xFF; outside that range fall back
    // to the 5x8 glyph with two empty descender rows.
    if (code >= 0xE0 && code <= 0xFF) {
      const off = (code - 0xE0) * 10;
      return FONT5X10.subarray(off, off + 10);
    }
    const r = rom5x8(code);
    const out = new Uint8Array(10);
    for (let i = 0; i < 8; i++) out[i] = r[i];
    return out;
  }

  // ===== LCD render =====
  const DOT = 3;           // each "pixel" is 3x3 css pixels
  const GAP = 1;           // 1 px gap between pixels
  const COLS_PER_CHAR = 5;
  const CELL_PAD_X = 2;    // 2 dots between adjacent character cells
  const CELL_PAD_Y = 2;    // 2 dots between LCD lines
  const LCD_MARGIN = 8;    // px around the whole grid inside the canvas

  function glyphFor(code, cgram, font5x10) {
    // Returns a Uint8Array of length rows*5, one byte per dot
    // (0 or 1). CGRAM hits codes 0x00..0x0F (lower 4 bits matter).
    const rows = font5x10 ? 10 : 8;
    const bitmap = new Uint8Array(COLS_PER_CHAR * rows);
    const isCgram = code <= 0x0F;
    let glyph;
    if (isCgram) {
      if (font5x10) {
        // 4 slots of 11 bytes (10 dot rows; the 11th is the cursor
        // row, ignored here). Char-code bits 1..3 select the slot.
        const slot = (code >> 1) & 0x03;
        const base = slot * 11;
        glyph = new Uint8Array(10);
        for (let i = 0; i < 10; i++) glyph[i] = cgram[base + i] || 0;
      } else {
        // 8 slots, 8 bytes/slot. Code bits 0..2 select slot.
        const slot = code & 0x07;
        const base = slot * 8;
        glyph = new Uint8Array(8);
        for (let i = 0; i < 8; i++) glyph[i] = cgram[base + i] || 0;
      }
    } else {
      glyph = font5x10 ? rom5x10(code) : rom5x8(code);
    }
    for (let yy = 0; yy < rows; yy++) {
      const row = (glyph[yy] || 0) & 0x1F;
      for (let xx = 0; xx < COLS_PER_CHAR; xx++) {
        bitmap[yy * COLS_PER_CHAR + xx] = (row >> (4 - xx)) & 1;
      }
    }
    return { bitmap, rows };
  }

  function renderLcd(canvas, lcd) {
    const { rows, cols, ddram, cgram, cur, cur_on, blink_on, disp_on, f5x10 } = lcd;
    const font5x10 = !!f5x10;
    const glyphRows = font5x10 ? 10 : 8;
    // Each cell on a real HD44780 LCD has one extra row below the glyph
    // for the underline cursor: 8+1 = 9 for 5x8, 10+1 = 11 for 5x10.
    const rowsPerCell = glyphRows + 1;
    const cellW = COLS_PER_CHAR * (DOT + GAP);
    const cellH = rowsPerCell * (DOT + GAP);
    const padX  = CELL_PAD_X * DOT;
    const padY  = CELL_PAD_Y * DOT;
    const innerW = cols * cellW + (cols - 1) * padX;
    const innerH = rows * cellH + (rows - 1) * padY;
    const W = innerW + LCD_MARGIN * 2;
    const H = innerH + LCD_MARGIN * 2;

    if (canvas.width !== W || canvas.height !== H) {
      canvas.width = W;
      canvas.height = H;
    }
    const ctx = canvas.getContext("2d");

    const bg = getComputedStyle(document.documentElement).getPropertyValue("--lcd-bg").trim() || "#7a9438";
    const onCol = getComputedStyle(document.documentElement).getPropertyValue("--lcd-on").trim() || "#1a2a08";
    const offCol = getComputedStyle(document.documentElement).getPropertyValue("--lcd-off").trim() || "#6e8731";
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, W, H);

    // Blink phase: alternates ~every 400 ms.
    const blinkPhase = (Math.floor(Date.now() / 400) & 1);

    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const code = ddram[r * cols + c];
        const cellX0 = LCD_MARGIN + c * (cellW + padX);
        const cellY0 = LCD_MARGIN + r * (cellH + padY);
        const { bitmap } = glyphFor(code, cgram, font5x10);
        const cursorHere = disp_on && cur && cur[0] === r && cur[1] === c;
        const blinkInvert = cursorHere && blink_on && blinkPhase === 0;

        for (let yy = 0; yy < rowsPerCell; yy++) {
          for (let xx = 0; xx < COLS_PER_CHAR; xx++) {
            let on;
            if (yy < glyphRows) {
              on = bitmap[yy * COLS_PER_CHAR + xx];
            } else {
              // Underline cursor row.
              on = (cursorHere && cur_on) ? 1 : 0;
            }
            if (blinkInvert) on = 1;
            ctx.fillStyle = on ? onCol : offCol;
            const px = cellX0 + xx * (DOT + GAP);
            const py = cellY0 + yy * (DOT + GAP);
            ctx.fillRect(px, py, DOT, DOT);
          }
        }
      }
    }
  }

  // ===== Pins panel =====
  function fmtBitsRow(rowId, val, ddr) {
    const tr = $(rowId);
    if (!tr) return;
    const cells = tr.querySelectorAll(".b");
    for (let i = 7; i >= 0; i--) {
      const idx = 7 - i;
      const cell = cells[idx];
      const bit = (val >> i) & 1;
      cell.textContent = String(bit);
      cell.classList.toggle("hi", bit === 1);
    }
    tr.querySelector(".ddr").textContent =
      "DDR=$" + ddr.toString(16).padStart(2, "0").toUpperCase();
  }

  function render(s) {
    renderLcd($("lcd"), s.lcd);
    $("led-morse").classList.toggle("on", !!s.led.morse);
    $("led-control").classList.toggle("on", !!s.led.control);
    $("btn-press").classList.toggle("held", !!s.btn.pressed);
    fmtBitsRow("row-a", s.porta, s.ddra);
    fmtBitsRow("row-b", s.portb, s.ddrb);
    $("status-clock").textContent =
      `osc:${s.osc}  cpu:${s.cpu}  pc:$${s.pc.toString(16).padStart(4, "0").toUpperCase()}` +
      (s.stp ? "  [STP]" : "");
  }

  // ===== WebSocket =====
  let ws = null;
  let audioCtx = null;
  let audioRate = 22050;
  let audioNextTime = 0;

  function ensureAudioContext() {
    if (audioCtx) return audioCtx;
    try {
      audioCtx = new (window.AudioContext || window.webkitAudioContext)({
        sampleRate: audioRate,
      });
    } catch (e) {
      // Some browsers reject explicit sample rates; fall back to default.
      audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    }
    audioNextTime = audioCtx.currentTime + 0.1;  // small head-start
    return audioCtx;
  }

  function playAudioFrame(int16) {
    if (!audioCtx) return;
    if (int16.length === 0) return;
    const buf = audioCtx.createBuffer(1, int16.length, audioRate);
    const ch = buf.getChannelData(0);
    for (let i = 0; i < int16.length; i++) ch[i] = int16[i] / 32768;
    const src = audioCtx.createBufferSource();
    src.buffer = buf;
    src.connect(audioCtx.destination);
    const now = audioCtx.currentTime;
    if (audioNextTime < now + 0.02) audioNextTime = now + 0.02; // resync
    src.start(audioNextTime);
    audioNextTime += int16.length / audioRate;
  }

  function handleBinary(buf) {
    const u8 = new Uint8Array(buf);
    if (u8.length < 1) return;
    if (u8[0] !== 0x01) return; // unknown tag
    const samples = (u8.length - 1) >> 1;
    const i16 = new Int16Array(samples);
    const dv = new DataView(u8.buffer, u8.byteOffset, u8.byteLength);
    for (let i = 0; i < samples; i++) i16[i] = dv.getInt16(1 + i * 2, true);
    playAudioFrame(i16);
  }

  function send(obj) {
    if (ws && ws.readyState === 1) ws.send(JSON.stringify(obj));
  }

  function setConn(state, msg) {
    const dot = $("status-conn");
    const txt = $("status-text");
    dot.classList.remove("ok", "off");
    dot.classList.add(state === "ok" ? "ok" : "off");
    txt.textContent = msg;
  }

  function connect() {
    setConn("off", "connecting…");
    const proto = location.protocol === "https:" ? "wss:" : "ws:";
    ws = new WebSocket(`${proto}//${location.host}/`);
    ws.binaryType = "arraybuffer";
    ws.onopen = () => setConn("ok", "connected");
    ws.onmessage = (e) => {
      if (typeof e.data === "string") {
        let obj;
        try { obj = JSON.parse(e.data); } catch { return; }
        if (obj.type === "audio_init") {
          audioRate = obj.rate;
          // Don't ensureAudioContext here -- browsers want a user
          // gesture first. We'll start it on the first button click
          // or focus.
        } else if (obj.lcd) {
          render(obj);
        }
      } else {
        handleBinary(e.data);
      }
    };
    ws.onclose = () => { setConn("off", "disconnected, retrying…"); setTimeout(connect, 500); };
    ws.onerror = () => { setConn("off", "ws error"); };
  }

  // Audio context init on first user gesture (browser policy).
  function unlockAudio() {
    if (!audioCtx) ensureAudioContext();
    if (audioCtx && audioCtx.state === "suspended") audioCtx.resume();
  }

  const btn = $("btn-press");
  btn.addEventListener("pointerdown", (e) => { unlockAudio(); btn.classList.add("held"); send({ type: "button", down: 1 }); e.preventDefault(); });
  btn.addEventListener("pointerup",   () => { btn.classList.remove("held"); send({ type: "button", down: 0 }); });
  btn.addEventListener("pointerleave",() => { if (btn.classList.contains("held")) { btn.classList.remove("held"); send({ type: "button", down: 0 }); } });
  // Reset button: one-shot {type:"reset"} on click. The server pulses
  // bus->res high for several oscillator ticks; the CPU and VIA see
  // the rising edge and clear their state.
  const rst = $("btn-reset");
  function fireReset() {
    rst.classList.add("flash");
    setTimeout(() => rst.classList.remove("flash"), 120);
    send({ type: "reset" });
  }
  rst.addEventListener("click", (e) => { unlockAudio(); fireReset(); e.preventDefault(); });

  // Keyboard: space toggles button; 'r' / 'R' triggers reset.
  let spaceDown = false;
  document.addEventListener("keydown", (e) => {
    if (e.key === " " && !spaceDown) {
      spaceDown = true; unlockAudio();
      btn.classList.add("held"); send({ type: "button", down: 1 });
      e.preventDefault();
    } else if (e.key === "r" || e.key === "R") {
      unlockAudio(); fireReset(); e.preventDefault();
    }
  });
  document.addEventListener("keyup",   (e) => { if (e.key === " ") { spaceDown = false; btn.classList.remove("held"); send({ type: "button", down: 0 }); e.preventDefault(); } });
  // Also: any click on the document unlocks audio (browser-gesture policy).
  document.addEventListener("click", unlockAudio, { once: false });

  connect();
})();
