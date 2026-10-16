#!/usr/bin/env python3
"""Serves the Web export (build/web) for local and phone testing.

Usage: python3 tools/export/serve_web.py [dir] [--port 8060] [--host 0.0.0.0]

* Sends Cross-Origin-Opener-Policy / Cross-Origin-Embedder-Policy headers, so a threaded
  build would also run (our preset ships without threads, which needs no special headers).
* Correct MIME types for .wasm / .pck, no caching (always the latest export).
* Serves pre-compressed `.gz` siblings when the browser accepts gzip.
* With --host 0.0.0.0 a phone on the same Wi-Fi opens http://<this-machine-ip>:8060.
"""
import argparse
import http.server
import os
import socketserver

TYPES = {
	".wasm": "application/wasm",
	".pck": "application/octet-stream",
	".js": "application/javascript",
	".html": "text/html; charset=utf-8",
	".png": "image/png",
	".svg": "image/svg+xml",
	".json": "application/json",
}


class Handler(http.server.SimpleHTTPRequestHandler):
	def end_headers(self):
		self.send_header("Cross-Origin-Opener-Policy", "same-origin")
		self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
		self.send_header("Cross-Origin-Resource-Policy", "same-origin")
		self.send_header("Cache-Control", "no-store")
		super().end_headers()

	def guess_type(self, path):
		ext = os.path.splitext(path)[1].lower()
		return TYPES.get(ext, super().guess_type(path))

	def send_head(self):
		path = self.translate_path(self.path)
		gz = path + ".gz"
		if os.path.isfile(path) and os.path.isfile(gz) and "gzip" in self.headers.get("Accept-Encoding", ""):
			f = open(gz, "rb")
			fs = os.fstat(f.fileno())
			self.send_response(200)
			self.send_header("Content-Type", self.guess_type(path))
			self.send_header("Content-Encoding", "gzip")
			self.send_header("Content-Length", str(fs.st_size))
			self.end_headers()
			return f
		return super().send_head()

	def log_message(self, fmt, *args):
		if os.environ.get("SERVE_QUIET"):
			return
		super().log_message(fmt, *args)


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("dir", nargs="?", default=os.path.join(os.path.dirname(__file__), "..", "..", "build", "web"))
	ap.add_argument("--port", type=int, default=8060)
	ap.add_argument("--host", default="127.0.0.1")
	a = ap.parse_args()
	os.chdir(os.path.abspath(a.dir))
	socketserver.TCPServer.allow_reuse_address = True
	with socketserver.ThreadingTCPServer((a.host, a.port), Handler) as httpd:
		print("serving %s on http://%s:%d" % (os.getcwd(), a.host, a.port), flush=True)
		httpd.serve_forever()


if __name__ == "__main__":
	main()
