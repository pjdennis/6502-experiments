// placeholder; full LCD/CGRAM render lands in the next commit
(() => {
  const $ = (id) => document.getElementById(id);
  const status = $("status-text");
  const lcd = $("lcd");
  const ctx = lcd.getContext("2d");
  const btn = $("btn-press");
  const ledMorse = $("led-morse");
  const ledCtrl  = $("led-control");
  const portaBits = $("porta-bits");
  const portbBits = $("portb-bits");
  const portaMeta = $("porta-meta");
  const portbMeta = $("portb-meta");

  let ws = null;
  let lastState = null;

  function fmtBits(v) {
    let s = "";
    for (let i = 7; i >= 0; i--) s += ((v >> i) & 1) ? "1" : "0";
    return s.split("").join(" ");
  }

  function renderLcd(s) {
    const { rows, cols, ddram } = s.lcd;
    const cw = 18, ch = 28, pad = 4;
    lcd.width = cols * cw + pad * 2;
    lcd.height = rows * ch + pad * 2;
    ctx.fillStyle = "#6f8a3a";
    ctx.fillRect(0, 0, lcd.width, lcd.height);
    ctx.fillStyle = "#1f2810";
    ctx.font = "20px monospace";
    ctx.textBaseline = "top";
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const code = ddram[r * cols + c];
        let ch_str;
        if (code >= 0x20 && code <= 0x7e) ch_str = String.fromCharCode(code);
        else ch_str = "?";
        ctx.fillText(ch_str, pad + c * cw + 2, pad + r * ch + 4);
      }
    }
  }

  function render(s) {
    renderLcd(s);
    ledMorse.classList.toggle("on", !!s.led.morse);
    ledCtrl.classList.toggle("on",  !!s.led.control);
    btn.classList.toggle("held", !!s.btn.pressed);
    portaBits.textContent = fmtBits(s.porta);
    portbBits.textContent = fmtBits(s.portb);
    portaMeta.textContent = "DDRA=$" + s.ddra.toString(16).padStart(2, "0").toUpperCase();
    portbMeta.textContent = "DDRB=$" + s.ddrb.toString(16).padStart(2, "0").toUpperCase();
    status.textContent =
      `osc:${s.osc}  cpu:${s.cpu}  pc:$${s.pc.toString(16).padStart(4, "0").toUpperCase()}` +
      (s.stp ? "  [STP]" : "");
  }

  function send(obj) {
    if (ws && ws.readyState === 1) ws.send(JSON.stringify(obj));
  }

  function connect() {
    const proto = location.protocol === "https:" ? "wss:" : "ws:";
    ws = new WebSocket(`${proto}//${location.host}/`);
    ws.onopen = () => { status.textContent = "connected, waiting for state…"; };
    ws.onmessage = (e) => {
      try {
        lastState = JSON.parse(e.data);
        render(lastState);
      } catch (err) {
        status.textContent = "parse error: " + err;
      }
    };
    ws.onclose = () => { status.textContent = "disconnected"; setTimeout(connect, 500); };
    ws.onerror = () => { status.textContent = "ws error"; };
  }

  btn.addEventListener("pointerdown", () => send({ type: "button", down: 1 }));
  btn.addEventListener("pointerup",   () => send({ type: "button", down: 0 }));
  btn.addEventListener("pointerleave",() => send({ type: "button", down: 0 }));

  connect();
})();
