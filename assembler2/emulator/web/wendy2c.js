// wendy2c web UI: state via WS JSON, audio via WS binary, LCD as
// per-pixel canvas render using the host 8x8 column-major font for
// ASCII and the streamed 5x8 CGRAM bitmaps for character codes
// 0x00..0x07.

(() => {
  const $ = (id) => document.getElementById(id);

  // ===== 8x8 column-major bitmap font for ASCII 0x20..0x7F =====
  // Each byte = one column, bit 0 = top pixel. Sourced from the
  // repo's character_patterns.inc.
  const FONT_B64 =
    "AAAAAAAAAAAAAAZfXwYAAAADAwADAwAAFH9/FH9/FAAkLmtrOhIAAEZmMBgMZmIAMHpPXTd6SAAE" +
    "BwMAAAAAAAAcPmNBAAAAAEFjPhwAAAAIKj4cHD4qCAgIPj4ICAAAAIDgYAAAAAAICAgICAgAAAAA" +
    "YGAAAAAAYDAYDAYDAQA+f3FZTX8+AEBCf39AQAAAYnNZSW9mAAAiY0lJfzYAABgcFlN/f1AAJ2dF" +
    "RX05AAA8fktJeTAAAAMDcXkPBwAANn9JSX82AAAGT0lpPx4AAAAAZmYAAAAAAIDmZgAAAAAIHDZj" +
    "QQAAACQkJCQkJAAAAEFjNhwIAAACA1FZDwYAAD5/QV1dHx4AfH4TE358AABBf39JSX82ABw+Y0FB" +
    "YyIAQX9/QWM+HABBf39JXUFjAEF/f0kdAQMAHD5jQVFzcgB/fwgIf38AAABBf39BAAAAMHBAQX8/" +
    "AQBBf38IHHdjAEF/f0FAYHAAf38OHA5/fwB/fwYMGH9/ABw+Y0FjPhwAQX9/SQkPBgAePyFxf14A" +
    "AEF/fwkZf2YAJm9NWXMyAAADQX9/QQMAAH9/QEB/fwAAHz9gYD8fAAB/fzAYMH9/AENnPBg8Z0MA" +
    "B094eE8HAABHY3FZTWdzAAB/f0FBAAAAAQMGDBgwYAAAQUF/fwAAAAgMBgMGDAgAgICAgICAgIAA" +
    "AAMHBAAAACB0VFQ8eEAAQX8/SEh4MAA4fEREbCgAADB4SEk/f0AAOHxUVFwYAABIfn9JAwIAAJi8" +
    "pKT4fAQAQX9/CAR8eAAARH19QAAAAGDggID9fQAAQX9/EDhsRAAAQX9/QAAAAHx8GDgcfHgAfHwE" +
    "BHx4AAA4fEREfDgAAIT8+KQkPBgAGDwkpPj8hABEfHhMBBwYAEhcVFR0JAAAAAQ+f0QkAAA8fEBA" +
    "PHxAABw8YGA8HAAAPHxwOHB8PABEbDgQOGxEAJy8oKD8fAAATGR0XExkAAAICD53QUEAAAAAAHd3" +
    "AAAAQUF3PggIAAACAwEDAgMBAA==";
  const FONT = Uint8Array.from(atob(FONT_B64), (ch) => ch.charCodeAt(0));
  // chars start at 0x20; 8 bytes per char
  function fontGlyphBytes(code) {
    if (code < 0x20 || code > 0x7F) return null;
    const off = (code - 0x20) * 8;
    return FONT.subarray(off, off + 8);
  }

  // ===== LCD render =====
  // Layout: each character cell is CELL_W x CELL_H pixels, made of
  // PX cells DOT x DOT each plus 1 px gap. ASCII uses the 8-col host
  // font; CGRAM uses 5 cols centered with 1.5-col padding (offset 1).
  const DOT = 3;           // each "pixel" is 3x3 css pixels
  const GAP = 1;           // 1 px gap between pixels
  const COLS_PER_CHAR = 5; // HD44780 5x8 cell
  const ROWS_PER_CHAR = 8;
  const CELL_PAD_X = 2;    // 2 dots between adjacent character cells
  const CELL_PAD_Y = 2;    // 2 dots between LCD lines
  const LCD_MARGIN = 8;    // px around the whole grid inside the canvas

  function renderLcd(canvas, lcd) {
    const { rows, cols, ddram, cgram } = lcd;
    const cellW = COLS_PER_CHAR * (DOT + GAP);
    const cellH = ROWS_PER_CHAR * (DOT + GAP);
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

    // Backlight wash.
    const bg = getComputedStyle(document.documentElement).getPropertyValue("--lcd-bg").trim() || "#7a9438";
    const onCol = getComputedStyle(document.documentElement).getPropertyValue("--lcd-on").trim() || "#1a2a08";
    const offCol = getComputedStyle(document.documentElement).getPropertyValue("--lcd-off").trim() || "#6e8731";
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, W, H);

    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const code = ddram[r * cols + c];
        const cellX0 = LCD_MARGIN + c * (cellW + padX);
        const cellY0 = LCD_MARGIN + r * (cellH + padY);

        // Build a 5x8 bitmap for this cell.
        // For ASCII, the host font is 8 cols. We pick the central 5
        // cols (cols 1..5) which holds the glyph for most chars.
        // For CGRAM, the streamed data is 8 rows of 5 columns.
        const bitmap = new Uint8Array(COLS_PER_CHAR * ROWS_PER_CHAR);
        if (code <= 0x07 || (code >= 0x08 && code <= 0x0F)) {
          // CGRAM. Codes 0x00..0x07 select slots 0..7; codes
          // 0x08..0x0F also map to slots 0..7 on the HD44780.
          const slot = code & 0x07;
          for (let yy = 0; yy < ROWS_PER_CHAR; yy++) {
            const row = cgram[slot * 8 + yy] & 0x1F;
            for (let xx = 0; xx < COLS_PER_CHAR; xx++) {
              // CGRAM row bit layout: MSB-of-low-5-bits = leftmost.
              const pix = (row >> (4 - xx)) & 1;
              bitmap[yy * COLS_PER_CHAR + xx] = pix;
            }
          }
        } else {
          const bytes = fontGlyphBytes(code);
          if (bytes) {
            for (let xx = 0; xx < COLS_PER_CHAR; xx++) {
              // Use cols 1..5 of the 8-col host font (col 0 is usually blank).
              const col = bytes[xx + 1];
              for (let yy = 0; yy < ROWS_PER_CHAR; yy++) {
                bitmap[yy * COLS_PER_CHAR + xx] = (col >> yy) & 1;
              }
            }
          }
        }

        // Paint pixels (off pixels too, faintly, for the LCD dot grid look).
        for (let yy = 0; yy < ROWS_PER_CHAR; yy++) {
          for (let xx = 0; xx < COLS_PER_CHAR; xx++) {
            const on = bitmap[yy * COLS_PER_CHAR + xx];
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
