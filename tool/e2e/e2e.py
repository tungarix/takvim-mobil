"""Takvim masaustu <-> mobil senkron UCTAN UCA dogrulama kosucusu.

Kullanim (takvim-mobil kokunden; tek komut icin `tool/e2e/calistir.ps1`):
    <takvim>/.venv/Scripts/python.exe tool/e2e/e2e.py [--senaryo a,b,c,d,e,olcek,f,wifi] [--tut]

Masaustu kodu GECICI SQLite ile, mobil kodu GECICI JSON ile surulur; gercek kullanici
verisine dokunulmaz. Cikis kodu 0 = tum denetimler gecti.
"""
from __future__ import annotations

import argparse
import shutil
import sys
import tempfile
import time
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from cihazlar import MobilSunucu  # noqa: E402
from senaryolar import SENARYOLAR as ESKI, Baglam  # noqa: E402
from wifi_senaryolar import SENARYOLAR as WIFI  # noqa: E402

SENARYOLAR = {**ESKI, **WIFI}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--senaryo", default=",".join(SENARYOLAR))
    ap.add_argument("--tut", action="store_true", help="gecici dizini silme")
    ap.add_argument("-v", action="store_true", help="gecen denetimleri de listele")
    a = ap.parse_args()
    secilen = [s.strip() for s in a.senaryo.split(",") if s.strip()]
    kok = Path(tempfile.mkdtemp(prefix="takvim-e2e-"))
    t0 = time.perf_counter()
    sunucu = MobilSunucu()
    ctx = Baglam(sunucu, kok)
    ozet = []
    try:
        for ad in secilen:
            ctx.senaryo = ad
            n0, ts = len(ctx.sonuclar), time.perf_counter()
            try:
                SENARYOLAR[ad](ctx)
            except Exception:
                ctx.kontrol("senaryo hatasiz tamamlandi", False, traceback.format_exc(limit=6).strip().splitlines()[-1])
                print(traceback.format_exc())
            finally:
                ctx.kapat()
            yeni = ctx.sonuclar[n0:]
            gecen = sum(1 for r in yeni if r[2])
            ozet.append((ad, gecen, len(yeni) - gecen, time.perf_counter() - ts))
            print(f"[{ad}] {gecen}/{len(yeni)} gecti ({time.perf_counter() - ts:.1f} sn)", flush=True)
    finally:
        sunucu.kapat()
        if not a.tut:
            shutil.rmtree(kok, ignore_errors=True)
    kalan = [r for r in ctx.sonuclar if not r[2]]
    if a.v:
        for s, ad, ok, _ in ctx.sonuclar:
            if ok:
                print(f"  gecti  [{s}] {ad}")
    for s, ad, _, detay in kalan:
        print(f"  KALDI  [{s}] {ad}\n         {detay[:600]}")
    if ctx.sure:
        print("\nOlcek sureleri (sn):")
        for k, v in ctx.sure.items():
            print(f"  {v:7.2f}  {k}")
    print(f"\nToplam: {len(ctx.sonuclar) - len(kalan)}/{len(ctx.sonuclar)} denetim gecti, {len(kalan)} kaldi, {time.perf_counter() - t0:.1f} sn")
    return 1 if kalan else 0


if __name__ == "__main__":
    sys.exit(main())
