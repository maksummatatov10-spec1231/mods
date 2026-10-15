#!/usr/bin/env python3
"""Tiny HTTP receiver: CI runners POST artifacts here (base64 or raw)."""
import http.server, os, json, time

OUT = "/home/user/exfil"
os.makedirs(OUT, exist_ok=True)

class H(http.server.BaseHTTPRequestHandler):
    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")

    def do_OPTIONS(self):
        self.send_response(204); self._cors(); self.end_headers()

    def do_GET(self):
        self.send_response(200); self._cors()
        self.send_header("Content-Type", "application/json"); self.end_headers()
        files = os.listdir(OUT)
        self.wfile.write(json.dumps({"ok": True, "files": files, "t": time.time()}).encode())

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        data = self.rfile.read(n)
        name = self.path.strip("/").replace("/", "_") or "blob.bin"
        safe = "".join(c for c in name if c.isalnum() or c in "._-")[:120]
        with open(os.path.join(OUT, safe), "wb") as f:
            f.write(data)
        print(f"RECV {safe} {len(data)} bytes", flush=True)
        self.send_response(200); self._cors()
        self.send_header("Content-Type", "text/plain"); self.end_headers()
        self.wfile.write(b"stored\n")

    def log_message(self, *a):
        pass

if __name__ == "__main__":
    http.server.HTTPServer(("0.0.0.0", 8099), H).serve_forever()
