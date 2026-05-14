#!/usr/bin/env python3
import base64
import html
import json
import os
import subprocess
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

CONFIG = Path("/etc/bobcat-miner/config.env")
WEBUI = Path("/etc/bobcat-miner/webui.env")
ALLOWED_SERVICES = {"helium-gateway", "bobcat-pktfwd", "bobcat-webui"}


def read_env(path):
    values = {}
    try:
        for raw in path.read_text().splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key] = value.strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    return values


def run(args, timeout=6):
    try:
        out = subprocess.check_output(args, stderr=subprocess.STDOUT, text=True, timeout=timeout)
        return out.strip()
    except subprocess.CalledProcessError as exc:
        return exc.output.strip()
    except Exception as exc:
        return str(exc)


def service_state(unit):
    return run(["systemctl", "is-active", f"{unit}.service"], timeout=3) or "unknown"


def status_payload():
    cfg = read_env(CONFIG)
    return {
        "hostname": run(["hostname"], timeout=2),
        "uptime": run(["uptime", "-p"], timeout=2),
        "region": cfg.get("BOBCAT_REGION", ""),
        "packet_forwarder_region": cfg.get("BOBCAT_PF_REGION", ""),
        "spi": cfg.get("BOBCAT_SPI_DEV", ""),
        "services": {unit: service_state(unit) for unit in sorted(ALLOWED_SERVICES)},
        "addresses": run(["ip", "-o", "-4", "addr", "show"], timeout=3),
        "disk": run(["df", "-h", "/"], timeout=3),
    }


def check_auth(handler):
    env = read_env(WEBUI)
    user = env.get("BOBCAT_WEBUI_USER", "admin")
    password = env.get("BOBCAT_WEBUI_PASSWORD", "bobcat")
    expected = "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()
    if handler.headers.get("Authorization") == expected:
        return True
    handler.send_response(401)
    handler.send_header("WWW-Authenticate", 'Basic realm="Bobcat 300"')
    handler.end_headers()
    return False


def page():
    data = status_payload()
    service_cards = []
    for name, state in data["services"].items():
        service_cards.append(
            f"<article><h3>{html.escape(name)}</h3><p class='state {html.escape(state)}'>{html.escape(state)}</p>"
            f"<button data-service='{html.escape(name)}'>Restart</button></article>"
        )
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Bobcat 300</title>
<style>
body{{margin:0;font:15px system-ui,-apple-system,Segoe UI,sans-serif;background:#f7f7f3;color:#20231f}}
header{{padding:22px 24px;background:#1f352e;color:white}}
main{{max-width:1100px;margin:0 auto;padding:24px;display:grid;gap:18px}}
h1{{font-size:24px;margin:0}} h2{{font-size:18px;margin:0 0 12px}} h3{{font-size:15px;margin:0 0 8px}}
.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:12px}}
section,article{{background:white;border:1px solid #d9ddd4;border-radius:8px;padding:16px}}
.state{{font-weight:700}} .active{{color:#16703b}} .inactive,.failed{{color:#a43a2e}}
button,input,select{{font:inherit}} button{{border:0;border-radius:6px;background:#285e4a;color:white;padding:9px 12px;cursor:pointer}}
button.secondary{{background:#555b63}} input{{border:1px solid #bfc7ba;border-radius:6px;padding:8px;width:100%;box-sizing:border-box}}
form{{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:10px;align-items:end}}
pre{{white-space:pre-wrap;overflow:auto;background:#111;color:#eee;border-radius:8px;padding:12px;max-height:360px}}
.meta{{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:10px}}
.meta div{{background:#eef2ea;border-radius:6px;padding:10px}}
</style>
</head>
<body>
<header><h1>Bobcat 300</h1></header>
<main>
<section>
<h2>Status</h2>
<div class="meta">
<div><strong>Host</strong><br>{html.escape(data["hostname"])}</div>
<div><strong>Uptime</strong><br>{html.escape(data["uptime"])}</div>
<div><strong>Region</strong><br>{html.escape(data["region"])} / {html.escape(data["packet_forwarder_region"])}</div>
<div><strong>SPI</strong><br>{html.escape(data["spi"])}</div>
</div>
</section>
<section><h2>Services</h2><div class="grid">{''.join(service_cards)}</div></section>
<section>
<h2>Region</h2>
<form id="region-form">
<label>Helium region<input name="region" value="{html.escape(data["region"] or "US915")}"></label>
<label>Packet forwarder region<input name="pf_region" value="{html.escape(data["packet_forwarder_region"] or "US915_SB2")}"></label>
<button>Apply</button>
</form>
</section>
<section><h2>Network</h2><pre>{html.escape(data["addresses"])}</pre></section>
<section><h2>Logs</h2><p><button class="secondary" data-log="helium-gateway">Gateway</button> <button class="secondary" data-log="bobcat-pktfwd">Packet Forwarder</button></p><pre id="logs"></pre></section>
</main>
<script>
async function post(url, body) {{
  const res = await fetch(url, {{method:'POST', headers:{{'content-type':'application/json'}}, body:JSON.stringify(body)}});
  if (!res.ok) alert(await res.text());
  else setTimeout(() => location.reload(), 800);
}}
document.querySelectorAll('button[data-service]').forEach(b => b.onclick = () => post('/api/restart', {{service:b.dataset.service}}));
document.querySelectorAll('button[data-log]').forEach(b => b.onclick = async () => {{
  document.getElementById('logs').textContent = await (await fetch('/api/logs?unit=' + encodeURIComponent(b.dataset.log))).text();
}});
document.getElementById('region-form').onsubmit = ev => {{
  ev.preventDefault();
  const form = new FormData(ev.target);
  post('/api/set-region', Object.fromEntries(form.entries()));
}};
</script>
</body>
</html>"""


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if not check_auth(self):
            return
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/status":
            self.send_json(status_payload())
        elif parsed.path == "/api/logs":
            qs = urllib.parse.parse_qs(parsed.query)
            unit = qs.get("unit", ["helium-gateway"])[0]
            if unit not in ALLOWED_SERVICES:
                self.send_error(400, "unknown unit")
                return
            text = run(["journalctl", "-u", f"{unit}.service", "-n", "160", "--no-pager"], timeout=8)
            self.send_text(text)
        else:
            self.send_html(page())

    def do_POST(self):
        if not check_auth(self):
            return
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode() if length else "{}"
        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            self.send_error(400, "invalid json")
            return
        if self.path == "/api/restart":
            service = data.get("service", "")
            if service not in ALLOWED_SERVICES:
                self.send_error(400, "unknown service")
                return
            subprocess.call(["systemctl", "restart", f"{service}.service"])
            self.send_json({"ok": True})
        elif self.path == "/api/set-region":
            region = data.get("region", "US915")
            pf_region = data.get("pf_region", region)
            rc = subprocess.call(["/usr/local/sbin/bobcat-set-region", region, pf_region])
            if rc:
                self.send_error(500, "failed to set region")
            else:
                self.send_json({"ok": True})
        else:
            self.send_error(404)

    def send_html(self, text):
        encoded = text.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def send_text(self, text):
        encoded = text.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def send_json(self, obj):
        encoded = json.dumps(obj, indent=2).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


def main():
    cfg = read_env(CONFIG)
    bind = os.environ.get("BOBCAT_WEBUI_BIND", cfg.get("BOBCAT_WEBUI_BIND", "0.0.0.0"))
    port = int(os.environ.get("BOBCAT_WEBUI_PORT", cfg.get("BOBCAT_WEBUI_PORT", "80")))
    ThreadingHTTPServer((bind, port), Handler).serve_forever()


if __name__ == "__main__":
    main()

