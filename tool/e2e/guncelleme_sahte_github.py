"""Güncelleme denemesi için sahte GitHub (yalnız geliştirme). Kullanım ve yöntem: docs/guncelleme-deneme.md"""
import hashlib
import http.server
import json
import pathlib
import sys

KLASOR = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else pathlib.Path(__file__).parent / "apk"
APK = (KLASOR / "yeni.apk").read_bytes()
OZET = hashlib.sha256(APK).hexdigest()
KOTU = len(sys.argv) > 1 and sys.argv[1] == "kotu"  # kötü senaryo: özet yanlış
ISTEKLER = []


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, f, *a):
        print("ISTEK", self.path, flush=True)

    def _yaz(self, kod, veri, tur="application/octet-stream"):
        self.send_response(kod)
        self.send_header("Content-Type", tur)
        self.send_header("Content-Length", str(len(veri)))
        self.end_headers()
        self.wfile.write(veri)

    def do_GET(self):
        taban = "http://10.0.2.2:8123"
        if self.path.endswith("/releases/latest"):
            veri = {
                "tag_name": "v0.4.0", "draft": False, "prerelease": False,
                "html_url": f"{taban}/sayfa",
                "assets": [
                    {"name": "Takvim-0.4.0.apk", "size": len(APK), "browser_download_url": f"{taban}/dl/Takvim-0.4.0.apk"},
                    {"name": "SHA256SUMS.txt", "size": 90, "browser_download_url": f"{taban}/dl/SHA256SUMS.txt"},
                ],
            }
            self._yaz(200, json.dumps(veri).encode(), "application/json")
        elif self.path == "/dl/Takvim-0.4.0.apk":
            self._yaz(200, APK)
        elif self.path == "/dl/SHA256SUMS.txt":
            ozet = ("0" * 64) if KOTU else OZET
            self._yaz(200, f"{ozet}  Takvim-0.4.0.apk\n".encode(), "text/plain")
        else:
            self._yaz(404, b"")


print("sahte github hazir", "(KOTU ozet)" if KOTU else "", flush=True)
http.server.ThreadingHTTPServer(("0.0.0.0", 8123), H).serve_forever()
