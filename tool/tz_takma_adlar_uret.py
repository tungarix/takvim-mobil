"""IANA takma adlarini (Link) `lib/core/tz_takma_adlar.dart`a uretir.

Dart `timezone` paketinin veritabani "backward" baglantilari icermiyor: masaustu
(Python zoneinfo) "UTC", "Europe/Amsterdam", "Asia/Calcutta", "US/Eastern" gibi adlari
kabul ediyor, mobil ise bu adli bir etkinlik iceren senkron dosyasini TUMUYLE reddediyordu.
Bu betik tzdata.zi'deki `L <hedef> <takma ad>` satirlarindan ad -> asil bolge tablosunu
cikarir; mobil `konumBul` once adin kendisini, bulamazsa bu tabloyu dener.

Kullanim (masaustunun .venv'iyle):
    <takvim>/.venv/Scripts/python.exe tool/tz_takma_adlar_uret.py lib/core/tz_takma_adlar.dart
Her takma adin hedefiyle 2000-2040 arasi UTC ofsetleri zoneinfo'da AYNI degilse uyarir.
"""
import sys
from datetime import datetime, timedelta, timezone
from importlib import resources
from zoneinfo import ZoneInfo

zi = resources.files("tzdata").joinpath("zoneinfo/tzdata.zi").read_text(encoding="utf-8")
link = {}
for satir in zi.splitlines():
    if satir.startswith("L "):
        _, hedef, ad = satir.split()
        link[ad] = hedef


def asil(ad):
    while ad in link:
        ad = link[ad]
    return ad


tablo = {ad: asil(ad) for ad in sorted(link)}
kotu = []
for ad, hedef in tablo.items():
    a, b = ZoneInfo(ad), ZoneInfo(hedef)
    t = datetime(2000, 1, 1, tzinfo=timezone.utc)
    while t.year < 2041:
        if a.utcoffset(t.replace(tzinfo=None)) != b.utcoffset(t.replace(tzinfo=None)):
            kotu.append((ad, hedef, t.date()))
            break
        t += timedelta(days=15)
with open(sys.argv[1], "w", encoding="utf-8", newline="\n") as f:
    f.write("// UTOMATIK URETILDI: tool/tz_takma_adlar_uret.py (elle degistirme).\n".replace("UTOMATIK", "OTOMATIK"))
    f.write("// IANA takma ad -> asil bolge. `timezone` paketinin veritabani bu adlari bilmiyor (bkz. betik).\n")
    f.write("const tzTakmaAdlar = <String, String>{\n")
    for ad, hedef in tablo.items():
        f.write(f"  '{ad}': '{hedef}',\n")
    f.write("};\n")
print(f"{len(tablo)} takma ad yazildi; ofset farki olan: {kotu}")
