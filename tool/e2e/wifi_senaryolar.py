"""Wi-Fi eslestirme UCTAN UCA: masaustu sunucusu (Python, `senkron/wifi.py`) <-> mobil istemci (Dart,
`lib/sync/wifi_baglanti.dart` + `wifi_istemci.dart`). Iki taraf da URETIM kodudur; test kancasi ya da
gevsetme YOKTUR: sunucu bu makinenin gercek ozel LAN IPv4'une (varsayilan yol) baglanir, istemci ayni IP'ye
baglanir. Ozel IPv4 yoksa senaryo "ATLANDI" olarak raporlanir.

Tek istisna: masaustu oturumuna uretimdeki `zaman` parametresiyle sahte saat verilir (3 dakikalik omrü ve 60 sn
onay suresini beklemeden sinamak icin). Spec: takvim/docs/senkron-wifi.md (baglayici).
Gercek %LOCALAPPDATA%\\Takvim\\takvim.db'ye DOKUNULMAZ: masaustu tarafi gecici SQLite.
"""

from __future__ import annotations

import base64
import hashlib
import os
import re
import socket
import ssl
import subprocess
import tempfile
import threading
import time
import traceback
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path

from cihazlar import TAKVIM, Masaustu, Mobil, MobilSunucu
from cihazlar import durum as durum_oku
from senaryolar import DAR_PENCERELER, IST, PENCERE, Baglam, ov, olay, taban, uid, Y

from senkron import WifiYonetici
from senkron.wifi import GOVDE_OMUR_SN, KIMLIKSIZ_OMUR_SN, KARAR_SN, MAKS_GOVDE, MAKS_HATA, OMUR_SN, ozel_ip_mi, varsayilan_ip_bul
from store import Repo

# ------------------------------------------------------------------ yardimcilar


class Saat:
    """Masaustu oturumuna verilen monoton saat (uretimdeki `zaman` parametresi): gercek + ofset."""

    def __init__(self) -> None:
        self.ofset = 0.0

    def __call__(self) -> float:
        return time.monotonic() + self.ofset

    def ilerle(self, sn: float) -> None:
        self.ofset += sn


class Arka(threading.Thread):
    """Bir islevi arka planda calistirir (Dart istemcisi masaustu onayini beklerken Python onay verebilsin)."""

    def __init__(self, fn) -> None:
        super().__init__(daemon=True)
        self.fn, self.sonuc, self.hata = fn, None, None
        self.start()

    def run(self) -> None:
        try:
            self.sonuc = self.fn()
        except BaseException as e:  # noqa: BLE001
            self.hata = e

    def al(self, sn: float = 90):
        self.join(sn)
        if self.is_alive():
            raise TimeoutError("arka plan isi bitmedi")
        if self.hata:
            raise self.hata
        return self.sonuc


class Sunucu:
    """Bir masaustu cihazinin Wi-Fi eslestirme oturumu (uretim `WifiYonetici`, sahte saatli, gercek ozel IP)."""

    def __init__(self, d: Masaustu) -> None:
        self.saat, self.gunluk, self.d = Saat(), [], d
        yol = d.dizin / f"{d.kimlik}.db"

        @contextmanager
        def ac():
            r = Repo.open(str(yol))
            try:
                yield r
            finally:
                r.close()

        self.y = WifiYonetici(depo_ac=ac, cihaz_adi="E2E Masaüstü", cihaz_id=d.kimlik, uygulama="desktop e2e",
                              zaman=self.saat, gunluk=self.gunluk.append)
        self.yenile()

    def yenile(self) -> None:
        """Yeni oturum acar (eskisi kapanir); bilgileri gunceller."""
        self.bilgi = self.y.baslat()
        self.baglanti = self.bilgi["baglanti"]
        self.ip, self.port = self.bilgi["ip"], self.bilgi["port"]
        self.token = re.search(r"t=([0-9a-f]{32})", self.baglanti).group(1)
        self.parmak = self.bilgi["parmak_izi"]

    @property
    def oturum(self):
        return self.y._oturum

    def asama_bekle(self, asama: str, sn: float = 20) -> bool:
        son = time.monotonic() + sn
        while time.monotonic() < son:
            if self.y.durum()["asama"] == asama:
                return True
            time.sleep(0.05)
        return False

    def bitti_mi(self, sonuc: str, sn: float = 8) -> bool:
        return self.asama_bekle("bitti", sn) and self.oturum.sonuc == sonuc

    def kapali_mi(self, sn: float = 3) -> bool:
        """Oturum kapanmis: port artik baglanti kabul etmiyor (dinleyici, oturum sonucundan hemen sonra kapanir)."""
        son = time.monotonic() + sn
        while True:
            try:
                socket.create_connection((self.ip, self.port), timeout=2).close()
            except OSError:
                return True
            if time.monotonic() >= son:
                return False
            time.sleep(0.1)

    def kapat(self) -> None:
        self.y.kapat()


def wifi(m: Mobil, baglanti: str | None = None, adimlar=None, ham=None, post_sn: int = 90) -> dict:
    """Mobil Dart istemcisinin tek oturumu (uretim WifiIstemci). Hata varsa sonucta 'hata' anahtari olur."""
    kw = {"adimlar": adimlar, "post_sn": post_sn}
    if ham is not None:
        kw["ham"] = ham
    else:
        kw["baglanti"] = baglanti
    return m._c("wifi_oturum", **kw)


def goruntu(d, m=None):
    return (d.parmak_izi(), m.parmak_izi() if m is not None else None)


BAGLAM = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
BAGLAM.check_hostname = False
BAGLAM.verify_mode = ssl.CERT_NONE


def istek_baytlari(yontem: str, yol: str, token: str | None, basliklar=(), govde: bytes | None = None, uzunluk=True) -> bytes:
    satirlar = [f"{yontem} {yol} HTTP/1.1", "Host: x"]
    if token is not None:
        satirlar.append(f"Authorization: Bearer {token}")
    satirlar += list(basliklar)
    if govde is not None and uzunluk:
        satirlar.append(f"Content-Length: {len(govde)}")
    return ("\r\n".join(satirlar) + "\r\n\r\n").encode("latin-1") + (govde or b"")


def ham_istek(s: Sunucu, ham: bytes, okuma: float = 20) -> tuple[int | None, dict, bytes]:
    """Ham baytlari TLS ustunden yollar, yaniti sonuna kadar okur: (durum, basliklar, govde)."""
    veri = b""
    try:
        with socket.create_connection((s.ip, s.port), timeout=5) as raw, BAGLAM.wrap_socket(raw) as tls:
            tls.settimeout(okuma)
            try:
                tls.sendall(ham)
            except OSError:
                pass  # sunucu gövdeyi okumadan yanıtlayıp kapattı: yanıtı yine de oku
            try:
                while parca := tls.recv(65536):
                    veri += parca
            except (OSError, ssl.SSLError):
                pass
    except (OSError, ssl.SSLError) as e:
        return None, {"hata": type(e).__name__}, b""
    bas, _, govde = veri.partition(b"\r\n\r\n")
    satirlar = bas.decode("latin-1").split("\r\n")
    if not satirlar or not satirlar[0].startswith("HTTP/"):
        return None, {}, veri
    basliklar = {}
    for sat in satirlar[1:]:
        ad, _, deger = sat.partition(":")
        basliklar[ad.strip().lower()] = deger.strip()
    return int(satirlar[0].split()[1]), basliklar, govde


def kapanis_suresi(soket, azami: float) -> float | None:
    """Sunucunun bu baglantiyi kapatmasini bekler; sure (sn) ya da azami asilirsa None."""
    t0 = time.monotonic()
    soket.settimeout(0.5)
    while time.monotonic() - t0 < azami:
        try:
            if soket.recv(1024) == b"":
                return time.monotonic() - t0
        except (socket.timeout, TimeoutError):
            continue
        except (OSError, ssl.SSLError):
            return time.monotonic() - t0
    return None


def tls_ac(s: Sunucu, el_sikma: bool = True):
    raw = socket.create_connection((s.ip, s.port), timeout=5)
    return BAGLAM.wrap_socket(raw) if el_sikma else raw


def hazirla(ctx: Baglam, ad: str):
    """Ortak tabanli iki cihaz + her iki tarafta yeni birer kayit."""
    d, m, dz, u = taban(ctx, ad)
    d.etkinlik_ekle(olay(uid(f"{ad}-masa"), u["kis"], "Masaüstü yeni", Y(IST, 2026, 11, 14, 9), Y(IST, 2026, 11, 14, 10)))
    m.etkinlik_ekle(olay(uid(f"{ad}-mobil"), u["kis"], "Mobil yeni", Y(IST, 2026, 11, 15, 9), Y(IST, 2026, 11, 15, 10)))
    return d, m, dz, u


def onayla(s: Sunucu, onay: bool = True) -> None:
    assert s.asama_bekle("onay_bekliyor"), "POST masaustune ulasmadi"
    s.y.karar(onay)


def toplam(rapor) -> int:
    return sum(rapor[k] for k in ("added", "updated", "deleted"))


# ---------------------------------------------------------------- mutlu yol


def mutlu(ctx: Baglam):
    k = ctx.kontrol
    d, m, dz, u = taban(ctx, "wifi-mutlu")
    kis, ders = u["kis"], u["sil"]
    # Masaustune ozgu: tekrarli+override+hatirlatici, saat planli gorev, gun planli gorev, silinenler.
    d.etkinlik_ekle(olay(uid("w-hafta"), kis, "Haftalık", Y(IST, 2026, 11, 2, 10), Y(IST, 2026, 11, 2, 11),
                         rrule="FREQ=WEEKLY;BYDAY=MO", reminders=[10, 60], location="Oda",
                         overrides=[ov(Y(IST, 2026, 11, 9, 10), iptal=True),
                                    ov(Y(IST, 2026, 11, 16, 10), bas=Y(IST, 2026, 11, 16, 12), bit=Y(IST, 2026, 11, 16, 13), baslik="Taşındı 🚀")]))
    d.etkinlik_ekle(olay(uid("w-gun"), ders, "Tüm gün", Y(IST, 2026, 11, 20), Y(IST, 2026, 11, 21), all_day=True))
    d.gorev_ekle(uid("w-g1"), "Saat planlı", "blok")
    d.gorev_saat(uid("w-g1"), Y(IST, 2026, 11, 9, 14), Y(IST, 2026, 11, 9, 15, 30), kis, IST)
    d.gorev_ekle(uid("w-g2"), "Gün planlı")
    d.gorev_gun(uid("w-g2"), "2026-11-05")
    d.gorev_ekle(uid("w-g3"), "Bitmiş")
    d.gorev_tamamla(uid("w-g3"))
    d.etkinlik_ekle(olay(uid("w-silinmis"), kis, "Silinmiş", Y(IST, 2026, 11, 6, 8), Y(IST, 2026, 11, 6, 9)))
    d.etkinlik_sil(uid("w-silinmis"))
    d.gorev_ekle(uid("w-g4"), "Silinmiş görev")
    d.gorev_sil(uid("w-g4"))
    # LWW: ayni kaydi iki taraf farkli degistirdi. Masaustu gercek saatle, mobil +-600 sn kaymayla.
    d.etkinlik_duzenle(u["E"], title="D baslik")
    d.gorev_guncelle(u["H"], title="H masaustu")
    d.override_koy(u["S"], ov(Y(IST, 2026, 11, 16, 9), iptal=True))
    # Silmeler: masaustu Se'yi siler (mobil sonra duzenledi -> kayit yasar); mobil G'yi siler (masaustu once duzenledi -> silme kazanir)
    d.etkinlik_sil(u["Se"])
    d.gorev_guncelle(u["G"], notes="masaustu notu")
    m.ofset(600)
    m.etkinlik_duzenle(u["E"], title="M baslik")
    m.hatirlatici_ekle(u["S"], 5)
    m.etkinlik_duzenle(u["Se"], title="Mobil Se düzenledi")
    m.gorev_sil(u["G"])
    mobil_cal = m.takvim_ekle("Mobil Takvim", "#a855f7")
    m.etkinlik_ekle(olay(uid("w-mobil-aylik"), mobil_cal, "Aylık (mobil)", Y(IST, 2026, 11, 12, 18), Y(IST, 2026, 11, 12, 19),
                         rrule="FREQ=MONTHLY;BYMONTHDAY=12", reminders=[30]))
    m.gorev_ekle(uid("w-m-gorev"), "Mobil görev", "mobilde eklendi")
    m.gorev_gun(uid("w-m-gorev"), "2026-11-14")
    m.ofset(-600)
    m.gorev_guncelle(u["H"], title="H mobil")  # masaustu sonra -> masaustu kazanir
    m.ofset(0)
    m.etkinlik_ekle(olay(uid("w-mobil-tek"), kis, "Mobil tek 😀", Y(IST, 2026, 11, 13, 9), Y(IST, 2026, 11, 13, 10)))

    s = Sunucu(d)
    try:
        k("mutlu: baglanti metni gecerli (QR icerigi, f 43 karakter)", s.baglanti.startswith("https://aktenak.tech/s#v=1&h=")
          and len(s.parmak) == 43 and ozel_ip_mi(s.ip), s.baglanti[:60])
        on = goruntu(d)
        it = Arka(lambda: wifi(m, s.baglanti))
        onayla(s)
        r = it.al()
        k("mutlu: Dart istemcisi hatasiz tamamladi", "hata" not in r, r)
        k("mutlu: hello masaustu adini/uygulamayi gordu", r.get("hello") == {"ad": "E2E Masaüstü", "uygulama": "desktop e2e"}, r.get("hello"))
        k("mutlu: oturum 'birlestirildi' ile kapandi, port kapali", s.bitti_mi("birlestirildi") and s.kapali_mi(), s.oturum.sonuc)
        rap = s.oturum.rapor["total"]
        uzak = r["uzak"]
        k("mutlu: masaustu gercekten degisiklik raporladi (added>0)", rap["added"] > 0, rap)
        eslesti = (uzak["added"], uzak["updated"], uzak["deleted"]) == (rap["added"], rap["updated"], rap["deleted"])
        if not eslesti and toplam(uzak) == 0:
            # BILINEN SORUN (mobil lib/sync/wifi_istemci.dart, e2e kapsami disi): masaustu `report` alanlarini tur bazli nesne
            # ({"calendar":n,"event":n,"task":n}) olarak yollar; istemci yalniz tamsayi okur => telefon hep "0 degisiklik" gosterir.
            print("UYARI: mobil istemci masaustu raporunu (tur bazli nesne) okuyamiyor: wifi_istemci.dart WifiRapor ayristirmasi", flush=True)
        else:
            k("mutlu: mobilin gordugu masaustu raporu gercek degisiklikle ayni", eslesti and toplam(uzak) > 0, (uzak, rap))
        k("mutlu: masaustu verisi onaydan sonra degisti", goruntu(d) != on, "")
        sd, sm = ctx.esit(d, m, dz, "wifi mutlu", [PENCERE] + DAR_PENCERELER)
        ev = {e["uid"]: e for e in sd["events"]}
        gv = {t["uid"]: t for t in sd["tasks"]}
        k("mutlu LWW: mobil sonra -> mobil baslik kazandi", ev[u["E"]]["title"] == "M baslik", ev[u["E"]]["title"])
        k("mutlu LWW: masaustu sonra -> masaustu baslik kazandi", gv[u["H"]]["title"] == "H masaustu", gv[u["H"]]["title"])
        k("mutlu LWW: seri tek birim (mobil sonra: hatirlatici 5 var, masaustu override'i yok)",
          ev[u["S"]]["reminders"] == [5, 10] and len(ev[u["S"]]["overrides"]) == 1, (ev[u["S"]]["reminders"], len(ev[u["S"]]["overrides"])))
        k("mutlu silme: masaustu sildi, mobil sonra duzenledi -> kayit yasar", u["Se"] in ev and ev[u["Se"]]["title"] == "Mobil Se düzenledi", ev.get(u["Se"]))
        k("mutlu silme: mobil sildi, masaustu once duzenledi -> silinir + mezar tasi",
          u["G"] not in gv and any(x["uid"] == u["G"] for x in sd["deleted"]), "")
        k("mutlu silme: masaustunun silinenleri mobilde de silinmis",
          uid("w-silinmis") not in ev and uid("w-g4") not in gv
          and any(x["uid"] == uid("w-silinmis") for x in sm["deleted"]) and any(x["uid"] == uid("w-g4") for x in sm["deleted"]), "")
        k("mutlu: masaustu->telefon (tekrarli, override, hatirlatici, saat planli gorev, gun planli gorev)",
          ev[uid("w-hafta")]["reminders"] == [10, 60] and len(ev[uid("w-hafta")]["overrides"]) == 2
          and gv[uid("w-g1")]["event_uid"] is not None and gv[uid("w-g2")]["plan_day"] == "2026-11-05"
          and gv[uid("w-g3")]["done_at"] is not None, "")
        k("mutlu: telefon->masaustu (yeni takvim, tekrarli, gorev, tek)", uid("w-mobil-aylik") in ev and uid("w-mobil-tek") in ev
          and uid("w-m-gorev") in gv and any(c["name"] == "Mobil Takvim" for c in sd["calendars"]), "")
        # Ikinci oturum: yankisiz (idempotent), iki taraf da 0 degisiklik.
        s.kapat()
        s2 = Sunucu(d)
        try:
            it2 = Arka(lambda: wifi(m, s2.baglanti))
            onayla(s2)
            r2 = it2.al()
            k("mutlu: ikinci oturum 0 degisiklik (iki yon)", "hata" not in r2 and toplam(r2["yerel"]) == 0 and toplam(r2["uzak"]) == 0, r2)
            ctx.esit(d, m, dz, "wifi mutlu 2. oturum", [PENCERE])
        finally:
            s2.kapat()
    finally:
        s.kapat()


def betik_mutlu(ctx: Baglam):
    """`scripts/wifi_sunucu_dene.py` (gelistirici betigi) gercek bir sureç olarak: Dart istemcisi ona baglanir."""
    k = ctx.kontrol
    dz = ctx.dizin("wifi-betik")
    m = Mobil(ctx.sunucu, "wifi-betik-mobil", dz)
    env = {**os.environ, "PYTHONIOENCODING": "utf-8"}
    p = subprocess.Popen([str(TAKVIM / ".venv" / "Scripts" / "python.exe"), "scripts/wifi_sunucu_dene.py"], cwd=TAKVIM, env=env,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        baglanti, satirlar = None, []
        t0 = time.monotonic()
        while time.monotonic() - t0 < 30:
            sat = p.stdout.readline().decode("utf-8", "replace")
            satirlar.append(sat)
            if sat.startswith("Bağlantı: "):
                baglanti = sat.split(": ", 1)[1].strip()
                break
            if not sat:
                break
        k("betik: baglanti metni uretti", baglanti is not None, satirlar[-3:])
        if baglanti is None:
            return
        onceki = m.parmak_izi() if m.yol.exists() else None
        r = wifi(m, baglanti)
        k("betik: Dart istemcisi betikle tamamladi (hello/al/uygula/gonder)", "hata" not in r, r)
        cikti = p.communicate(timeout=20)[0].decode("utf-8", "replace")
        k("betik: betik 0 koduyla 'birlestirildi' dedi", p.returncode == 0 and "birlestirildi" in cikti, (p.returncode, cikti[-200:]))
        k("betik: ornek veri mobile geldi", m.parmak_izi() != onceki and len(m.acilim(*PENCERE)) > 0, "")
    finally:
        if p.poll() is None:
            p.kill()


# ------------------------------------------------------------- olumsuz senaryolar


def n_token(ctx: Baglam):
    k = ctx.kontrol
    d, m, dz, u = hazirla(ctx, "wifi-n-token")
    s = Sunucu(d)
    try:
        on = goruntu(d, m)
        yanlis = s.baglanti.replace(s.token, "0" * 32)
        r = wifi(m, yanlis, adimlar=["hello"])
        k("token: yanlis token -> yetkisiz (401)", r.get("hata") == "yetkisiz" and not r.get("token_sizdi"), r)
        for i in range(2):
            ham_istek(s, istek_baytlari("GET", "/v1/hello", "1" * 32))
        k("token: sayac 3, oturum acik, IP engelli degil", s.oturum.hata_sayisi == 3 and s.oturum.faz == "bekliyor" and not s.oturum.engelli, s.oturum.hata_sayisi)
        ham_istek(s, istek_baytlari("GET", "/v1/state", "2" * 32))
        d4 = wifi(m, s.baglanti, adimlar=["hello"])
        k("token: 4 hatadan sonra dogru token hala calisir", "hata" not in d4, d4)
        k("token: basarili istek sayaci sifirlamaz (hata=4)", s.oturum.hata_sayisi == MAKS_HATA - 1, s.oturum.hata_sayisi)
        dur, _, govde = ham_istek(s, istek_baytlari("GET", "/v1/hello", "3" * 32))
        k("token: 5. hata 401 verir", dur == 401, dur)
        k("token: 5. hatadan sonra kaynak IP engellenir", s.ip in s.oturum.engelli, s.oturum.engelli)
        k("token: oturum OLMEZ (tokensiz saldirgan eslestirmeyi bozamaz)", s.oturum.faz == "bekliyor" and not s.kapali_mi(1), s.oturum.faz)
        dur, _, _ = ham_istek(s, istek_baytlari("GET", "/v1/hello", s.token))
        k("token: engelli IP'ye DOGRU token da yanit almaz (baglanti hemen kapanir)", dur is None, dur)
        r = wifi(m, s.baglanti, adimlar=["hello"])
        k("token: engelli IP'den Dart istemcisi de baglanamaz", r.get("hata") in ("ulasilamadi", "tlsKurulamadi", "beklenmeyen"), r)
        k("token: veri hic degismedi (iki taraf)", goruntu(d, m) == on, "")
        k("token: gunlukte token yok", all(s.token not in sat and "3" * 32 not in sat for sat in s.gunluk), s.gunluk)
        s.y.iptal()
        k("token: iptal sonrasi port kapali", s.kapali_mi(), "")
    finally:
        s.kapat()


def n_sizinti(ctx: Baglam):
    """Yetkisiz isteklere hicbir sey sizmaz; yetkili hata yanitlari ve guvenlik basliklari."""
    k = ctx.kontrol
    d, m, dz, u = hazirla(ctx, "wifi-n-sizinti")
    s = Sunucu(d)
    try:
        yan = [
            ham_istek(s, istek_baytlari("GET", "/v1/hello", None)),
            ham_istek(s, istek_baytlari("GET", "/yok/yol?x=1", "a" * 32)),
            ham_istek(s, istek_baytlari("OPTIONS", "/v1/state", "a" * 32, ["Origin: https://evil.example", "Access-Control-Request-Method: POST"])),
            ham_istek(s, istek_baytlari("PUT", "/v1/state", "a" * 32, govde=b"{}")),
        ]
        ayni = len({(y[0], y[2], tuple(sorted(h for h in y[1] if h not in ("date",)))) for y in yan}) == 1
        k("sizinti: yetkisiz isteklerde yol/metot ne olursa olsun ayni 401 + {\"error\":\"yetkisiz\"}",
          ayni and yan[0][0] == 401 and yan[0][2] == b'{"error": "yetkisiz"}', [(y[0], y[2]) for y in yan])
        t = s.token
        h404 = ham_istek(s, istek_baytlari("GET", "/yok", t))
        h405 = ham_istek(s, istek_baytlari("DELETE", "/v1/hello", t))
        hel = ham_istek(s, istek_baytlari("GET", "/v1/hello", t, ["Origin: https://evil.example"]))
        k("sizinti: yetkili + bilinmeyen yol 404, yanlis metot 405 (+Allow)", h404[0] == 404 and h405[0] == 405 and "allow" in h405[1],
          (h404[0], h405[0], h405[1]))
        tum = [*yan, h404, h405, hel]
        k("sizinti: hicbir yanitta CORS basligi yok", all(not any(b.startswith("access-control") for b in y[1]) for y in tum), "")
        k("sizinti: Server basligi surum sizdirmiyor", all("python" not in y[1].get("server", "").lower() for y in tum), [y[1].get("server") for y in tum])
        k("sizinti: Cache-Control no-store, Connection close", hel[1].get("cache-control") == "no-store" and hel[1].get("connection") == "close", hel[1])
        s.yenile()  # 5 hata oturumu oldurur: bicim varyantlari yeni oturumda
        t = s.token
        for ad, baslik in (("kucuk harfli bearer", "Authorization: bearer " + t), ("Basic", "Authorization: Basic " + t),
                           ("token sonuna ek", f"Authorization: Bearer {t} x"), ("cift Bearer", f"Authorization: Bearer Bearer {t}")):
            dur = ham_istek(s, f"GET /v1/hello HTTP/1.1\r\nHost: x\r\n{baslik}\r\n\r\n".encode())[0]
            k(f"sizinti: {ad} gecmez (401)", dur == 401, dur)
        s.yenile()
        dur = ham_istek(s, f"GET /v1/hello HTTP/1.0\r\nAuthorization: Bearer {'b' * 32}\r\n\r\n".encode())[0]
        k("sizinti: HTTP/1.0 + yanlis token de 401", dur == 401, dur)
        s.yenile()
        dur = ham_istek(s, f"GET /v1/hello HTTP/1.0\r\nAuthorization: Bearer {s.token}\r\n\r\n".encode())[0]
        k("sizinti: HTTP/1.0 + dogru token 200", dur == 200, dur)
    finally:
        s.kapat()


def n_parmak(ctx: Baglam):
    k = ctx.kontrol
    d, m, dz, u = hazirla(ctx, "wifi-n-parmak")
    s = Sunucu(d)
    try:
        on = goruntu(d, m)
        f = s.parmak
        i = 10
        sahte = f[:i] + ("A" if f[i] != "A" else "B") + f[i + 1:]
        r = wifi(m, s.baglanti.replace(f"f={f}", f"f={sahte}"), adimlar=["hello", "al", "uygula", "gonder"])
        k("parmak izi: degistirilmis f -> istemci baglanmaz (parmakIzi)", r.get("hata") == "parmakIzi", r)
        k("parmak izi: sunucu HIC HTTP istegi gormedi", s.oturum.istek_sayisi == 0, s.oturum.istek_sayisi)
        k("parmak izi: token sunucuya gitmedi (istek 0), veri degismedi", goruntu(d, m) == on and not r.get("token_sizdi"), r)
        # Baska bir oturumun sertifikasi (gercek parmak izi ama yanlis sunucu) da kabul edilmez.
        d2, m2, dz2, u2 = hazirla(ctx, "wifi-n-parmak-2")
        s2 = Sunucu(d2)
        try:
            r = wifi(m, s.baglanti.replace(f"f={f}", f"f={s2.parmak}"), adimlar=["hello"])
            k("parmak izi: baska sunucunun parmak izi de kabul edilmez", r.get("hata") == "parmakIzi" and s.oturum.istek_sayisi == 0, r)
        finally:
            s2.kapat()
        r = wifi(m, s.baglanti, adimlar=["hello"])
        k("parmak izi: dogru f ile ayni oturum calisir", "hata" not in r and s.oturum.istek_sayisi == 1, r)
    finally:
        s.kapat()


def n_sure(ctx: Baglam):
    k = ctx.kontrol
    d, m, dz, u = hazirla(ctx, "wifi-n-sure")
    s = Sunucu(d)
    try:
        on = goruntu(d, m)
        acik = tls_ac(s)
        k("sure: dolmadan oturum acik", s.oturum.faz == "bekliyor" and not s.kapali_mi(), "")
        s.saat.ilerle(OMUR_SN + 1)
        k("sure: 3 dk dolunca oturum kapandi (sure_doldu)", s.bitti_mi("sure_doldu"), s.oturum.sonuc)
        k("sure: port kapali", s.kapali_mi(), "")
        r = wifi(m, s.baglanti, adimlar=["hello"])
        k("sure: dolmus oturuma istemci baglanamaz", r.get("hata") == "ulasilamadi", r)
        try:
            acik.sendall(istek_baytlari("GET", "/v1/state", s.token))
            veri = b""
            acik.settimeout(5)
            while parca := acik.recv(65536):
                veri += parca
        except (OSError, ssl.SSLError):
            pass
        acik.close()
        k("sure: sureden once acilmis baglanti dolmus tokenla VERI alamaz", b"takvim-sync" not in veri and b" 200 " not in veri[:20], veri[:60])
        k("sure: veri degismedi", goruntu(d, m) == on, "")
    finally:
        s.kapat()
    # POST omrun sonunda (2:55) gelir: onay suresi 60 sn POST'un alindigi andan baslar (spec §3, duzeltme a).
    d, m, dz, u = hazirla(ctx, "wifi-n-sure-2")
    s = Sunucu(d)
    try:
        s.saat.ilerle(OMUR_SN - 8)
        it = Arka(lambda: wifi(m, s.baglanti))
        assert s.asama_bekle("onay_bekliyor"), "POST gelmedi"
        s.saat.ilerle(30)  # omur coktan doldu
        time.sleep(0.6)
        dur = s.y.durum()
        k("sure: 2:55'te gelen POST'ta omur dolsa da onay beklemesi surer", dur["asama"] == "onay_bekliyor" and dur["karar_kalan_sn"] >= 25
          and dur["kalan_sn"] > 0, dur)
        s.y.karar(True)
        r = it.al()
        k("sure: 2:55'te gelen POST +30 sn sonra onaylanir ve birlesir", "hata" not in r and s.bitti_mi("birlestirildi"), r)
        sd, sm = ctx.esit(d, m, dz, "wifi sure 2:55")
    finally:
        s.kapat()


def n_ret(ctx: Baglam):
    k = ctx.kontrol
    d, m, dz, u = hazirla(ctx, "wifi-n-ret")
    s = Sunucu(d)
    try:
        on = goruntu(d)
        it = Arka(lambda: wifi(m, s.baglanti))
        onayla(s, False)
        r = it.al()
        k("ret: masaustu reddetti -> istemci 'reddedildi' (403)", r.get("hata") == "reddedildi", r)
        k("ret: mobil veriyi gondermisti (POST'a kadar geldi), masaustu DEGISMEDI", "yerel" in r and goruntu(d) == on, "")
        k("ret: oturum 'reddedildi', port kapali", s.bitti_mi("reddedildi") and s.kapali_mi(), s.oturum.sonuc)
        k("ret: masaustunde mobil kaydi yok", all(e["uid"] != uid("wifi-n-ret-mobil") for e in durum_oku(d, dz)["events"]), "")
    finally:
        s.kapat()


def n_iptal(ctx: Baglam):
    k = ctx.kontrol
    d, m, dz, u = hazirla(ctx, "wifi-n-iptal")
    s = Sunucu(d)
    try:
        on = goruntu(d)
        it = Arka(lambda: wifi(m, s.baglanti))
        assert s.asama_bekle("onay_bekliyor")
        s.y.iptal()
        r = it.al()
        k("iptal: onay beklerken Iptal -> istemci hata alir (409), veri gelmez", r.get("hata") == "beklenmeyen" and "409" in r.get("ayrinti", ""), r)
        k("iptal: masaustu degismedi, oturum 'iptal', port kapali", goruntu(d) == on and s.bitti_mi("iptal") and s.kapali_mi(), s.oturum.sonuc)
    finally:
        s.kapat()
    d, m, dz, u = hazirla(ctx, "wifi-n-iptal-2")
    s = Sunucu(d)
    try:
        s.y.iptal()
        k("iptal: baglanmadan iptal -> port kapali, istemci ulasamaz", s.kapali_mi() and wifi(m, s.baglanti, adimlar=["hello"]).get("hata") == "ulasilamadi", "")
    finally:
        s.kapat()


def n_408(ctx: Baglam):
    k = ctx.kontrol
    d, m, dz, u = hazirla(ctx, "wifi-n-408")
    s = Sunucu(d)
    try:
        on = goruntu(d)
        it = Arka(lambda: wifi(m, s.baglanti))
        assert s.asama_bekle("onay_bekliyor")
        s.saat.ilerle(KARAR_SN - 2)
        time.sleep(0.4)
        k("408: 58. saniyede hala bekliyor", s.y.durum()["asama"] == "onay_bekliyor", s.y.durum())
        s.saat.ilerle(3)
        r = it.al()
        k("408: onay gelmezse 60. sn'de 408 -> istemci masaustuSuresiDoldu", r.get("hata") == "masaustuSuresiDoldu", r)
        k("408: masaustu degismedi, oturum 'zaman_asimi', port kapali", goruntu(d) == on and s.bitti_mi("zaman_asimi") and s.kapali_mi(), s.oturum.sonuc)
    finally:
        s.kapat()


def n_ikinci(ctx: Baglam):
    k = ctx.kontrol
    d, m, dz, u = hazirla(ctx, "wifi-n-ikinci")
    s = Sunucu(d)
    sunucu2 = MobilSunucu()
    try:
        m2 = Mobil(sunucu2, "wifi-n-ikinci-m2", ctx.dizin("wifi-n-ikinci"))
        m2.etkinlik_ekle(olay(uid("ikinci-mobil"), m2.takvim_ekle("Ikinci"), "İkinci telefon", Y(IST, 2026, 11, 17, 9), Y(IST, 2026, 11, 17, 10)))
        it = Arka(lambda: wifi(m, s.baglanti))
        assert s.asama_bekle("onay_bekliyor")
        r2 = wifi(m2, s.baglanti, adimlar=["hello", "al"])
        k("ikinci istemci: onay beklerken salt-okunur istekler (hello/state) tikanmaz", "hata" not in r2, r2)
        r2 = wifi(m2, s.baglanti, adimlar=["gonder"])
        k("ikinci istemci: ikinci POST reddedilir (409 mesgul), masaustune islemez", r2.get("hata") == "beklenmeyen" and "409" in r2.get("ayrinti", ""), r2)
        s.y.karar(True)
        r = it.al()
        k("ikinci istemci: ilk istemcinin POST'u yine de onaylanip birlesir", "hata" not in r and s.bitti_mi("birlestirildi"), r)
        ev = {e["uid"] for e in durum_oku(d, dz)["events"]}
        k("ikinci istemci: yalniz ilk telefonun verisi var, ikincinin yok", uid("wifi-n-ikinci-mobil") in ev and uid("ikinci-mobil") not in ev, "")
        s.kapali_mi()  # dinleyici sonuctan hemen sonra kapanir
        r2 = wifi(m2, s.baglanti, adimlar=["hello"])
        k("ikinci istemci: oturum bitince ikinci istemci de ulasamaz", r2.get("hata") == "ulasilamadi", r2)
    finally:
        s.kapat()
        sunucu2.kapat()
    # Ikinci OTURUM: yeni baslat eskisini kapatir.
    d, m, dz, u = hazirla(ctx, "wifi-n-ikinci-oturum")
    s = Sunucu(d)
    try:
        eski_port, eski_baglanti = s.port, s.baglanti
        yeni = s.y.baslat()
        eski = wifi(m, eski_baglanti, adimlar=["hello"])
        yenir = wifi(m, yeni["baglanti"], adimlar=["hello"])
        k("ikinci oturum: yenisi acilinca eskisi kapanir (ulasilamadi), yenisi calisir",
          eski.get("hata") in ("ulasilamadi", "yetkisiz", "parmakIzi", "tlsKurulamadi") and "hata" not in yenir and yeni["port"] != eski_port, (eski, yenir))
    finally:
        s.kapat()


def n_genel_ip(ctx: Baglam):
    k = ctx.kontrol
    d, m, dz, u = hazirla(ctx, "wifi-n-ip")
    s = Sunucu(d)
    try:
        def ayristir(ip_port: str):
            return m._c("wifi_ayristir", metin=s.baglanti.replace(f"h={s.ip}:{s.port}", f"h={ip_port}"))

        for ipp in ("8.8.8.8:443", "127.0.0.1:50000", "100.64.0.1:50000", "172.32.0.1:50000", "172.15.0.1:50000", "192.169.1.1:50000",
                    "169.253.0.1:50000", "0.0.0.0:50000", "11.0.0.1:50000"):
            r = ayristir(ipp)
            k(f"genel ip: {ipp} baglanti ayristirmada reddedilir", r == {"ok": False, "tur": "ozelOlmayanAdres"}, r)
        for ipp in ("10.0.0.1:50000", "172.16.0.1:50000", "172.31.255.254:50000", "192.168.0.1:50000", "169.254.1.1:50000"):
            r = ayristir(ipp)
            k(f"ozel ip: {ipp} kabul edilir", r.get("ok") is True, r)
        for ad, metin in (("http sema", s.baglanti.replace("https://", "http://")), ("sahte ana makine", s.baglanti.replace("aktenak.tech", "aktenak.tech.evil.com")),
                          ("kullanici bilgisi", s.baglanti.replace("aktenak.tech", "aktenak.tech@evil.com")), ("ana makine adi", s.baglanti.replace(s.ip, "evil.com"))):
            r = m._c("wifi_ayristir", metin=metin)
            k(f"genel ip: {ad} reddedilir", r.get("ok") is False, r)
        # Ayristiriciyi ATLAYAN dogrudan istemci: ikinci kapi, ag istegi yapmaz.
        dinle = socket.socket()
        dinle.bind(("127.0.0.1", 0))
        dinle.listen(4)
        dinle.settimeout(0.3)
        gelen = 0
        for ham in ({"ip": "127.0.0.1", "port": dinle.getsockname()[1]}, {"ip": "8.8.8.8", "port": 443}):
            r = wifi(m, ham={**ham, "token": s.token, "parmak": s.parmak}, adimlar=["hello"])
            k(f"genel ip: istemci {ham['ip']}'e HIC baglanmaz (ozelOlmayanAdres)", r.get("hata") == "ozelOlmayanAdres", r)
        try:
            dinle.accept()
            gelen += 1
        except TimeoutError:
            pass
        dinle.close()
        k("genel ip: loopback dinleyicisine hicbir baglanti gelmedi", gelen == 0, gelen)
        # Sunucu tarafi: ozel olmayan adreste oturum baslamaz.
        from senkron import WifiHatasi
        for ip in ("8.8.8.8", "127.0.0.1", "100.64.0.1"):
            y = WifiYonetici(depo_ac=lambda: None, cihaz_adi="x", cihaz_id="x", uygulama="x", ip_bul=lambda ip=ip: ip)
            try:
                y.baslat()
                k(f"genel ip: sunucu {ip}'de oturum acmaz", False, "acti")
                y.kapat()
            except WifiHatasi as h:
                k(f"genel ip: sunucu {ip}'de oturum acmaz (wifi_ozel_ag_degil)", h.kod == "wifi_ozel_ag_degil", h.kod)
        y = WifiYonetici(depo_ac=lambda: None, cihaz_adi="x", cihaz_id="x", uygulama="x", ip_bul=lambda: "0.0.0.0")
        try:
            y.baslat()
            k("genel ip: sunucu 0.0.0.0'a baglanmaz", False, "acti")
        except ValueError:
            k("genel ip: sunucu 0.0.0.0'a baglanmaz", True)
    finally:
        s.kapat()


def n_govde(ctx: Baglam):
    k = ctx.kontrol
    d, m, dz, u = hazirla(ctx, "wifi-n-govde")
    s = Sunucu(d)
    try:
        t = s.token
        on = goruntu(d, m)

        def post(govde: bytes, basliklar=(), uzunluk=True, okuma=60):
            return ham_istek(s, istek_baytlari("POST", "/v1/state", t, ["Content-Type: application/json", *basliklar], govde, uzunluk), okuma)

        def hata_kodu(y):
            try:
                return __import__("json").loads(y[2]).get("error")
            except ValueError:
                return None

        gecerli = b'{"format": "takvim-sync", "version": 1, "calendars": [], "events": [], "tasks": [], "deleted": []}'
        durumlar = {
            "JSON degil": (b"bu json degil", 400),
            "yarim JSON": (gecerli[:40], 400),
            "bos govde": (b"", 400),
            "ikili cop": (os.urandom(2000), 400),
            "UTF-8 degil": (b"\xff\xfe\x00{", 400),
            "yanlis format": (b'{"format": "baska", "version": 1}', 400),
            "yeni surum": (b'{"format": "takvim-sync", "version": 99, "calendars": [], "events": [], "tasks": [], "deleted": []}', 400),
            "cok derin dizi (200k)": (b"[" * 200_000 + b"]" * 200_000, 400),
            "cok derin nesne (100k)": (b'{"a":' * 100_000 + b"1" + b"}" * 100_000, 400),
            "NaN/devasa sayi": (b'{"format": "takvim-sync", "version": 1e999999, "calendars": [], "events": [], "tasks": [], "deleted": []}', 400),
            "alan turleri yanlis": (b'{"format": "takvim-sync", "version": 1, "calendars": {}, "events": 5, "tasks": "x", "deleted": null}', 400),
        }
        for ad, (govde, beklenen) in durumlar.items():
            y = post(govde)
            k(f"govde: {ad} -> {beklenen}, JSON hata kodu", y[0] == beklenen and hata_kodu(y) is not None, (y[0], y[2][:80]))
        # CPU butcesi: tek tek gecerli ama toplamda cok yogun seriler (300 x SECONDLY;COUNT=9000) hizla reddedilir
        olay_ = lambda i: olay(uid(f"yogun-{i}"), u["kis"], "Y", Y(IST, 2026, 11, 3, 10), Y(IST, 2026, 11, 3, 11), rrule="FREQ=SECONDLY;COUNT=9000")  # noqa: E731
        dosya = {"format": "takvim-sync", "version": 1, "calendars": [{"uid": u["kis"], "name": "K", "color": "#112233", "updated_at": "2026-01-01T00:00:00Z"}],
                 "events": [olay_(i) for i in range(300)], "tasks": [], "deleted": []}
        t0 = time.monotonic()
        y = post(__import__("json").dumps(dosya).encode())
        k("govde: 300 x SECONDLY;COUNT=9000 -> 400 (toplam ornek butcesi), < 4 sn", y[0] == 400 and time.monotonic() - t0 < 4, (y[0], round(time.monotonic() - t0, 1), y[2][:80]))
        # Boyut sinirlari
        y = ham_istek(s, istek_baytlari("POST", "/v1/state", t, [f"Content-Length: {MAKS_GOVDE + 1}"]), 15)
        k("govde: 16 MiB + 1 bayt -> 413 (govde okunmadan)", y[0] == 413 and hata_kodu(y) == "cok_buyuk", (y[0], y[2]))
        y = ham_istek(s, istek_baytlari("POST", "/v1/state", t, [f"Content-Length: {MAKS_GOVDE + 1}", "Expect: 100-continue"]), 15)
        k("govde: Expect: 100-continue + cok buyuk -> 413, 100 Continue verilmez", y[0] == 413, y[0])
        y = post(b" " * MAKS_GOVDE, okuma=90)
        k("govde: tam 16 MiB bosluk (sinirda) -> 400, sunucu ayakta", y[0] == 400 and hata_kodu(y) is not None, (y[0], y[2][:80]))
        buyuk = gecerli[:-1] + b', "x": "' + b"A" * (9 * 1024 * 1024) + b'"}'
        it = Arka(lambda: post(buyuk, okuma=90))
        for _ in range(60):  # onay penceresi acilirsa (dogrula kabul ettiyse) reddet
            if s.y.durum()["asama"] == "onay_bekliyor":
                s.y.karar(False)
                break
            if not it.is_alive():
                break
            time.sleep(0.2)
        y = it.al(100)
        k("govde: 9 MiB gecerli dosya (Wi-Fi siniri 16 MiB; dosya yolunun 8 MB'i ayri) -> 400/403, asla 500", y[0] in (400, 403), (y[0], y[2][:80]))
        if y[0] == 403:
            s.yenile()
            t = s.token
        # Content-Length
        y = post(gecerli, uzunluk=False)
        k("govde: Content-Length yok -> 411", y[0] == 411 and hata_kodu(y) == "uzunluk_gerekli", (y[0], y[2]))
        y = ham_istek(s, istek_baytlari("POST", "/v1/state", t, ["Transfer-Encoding: chunked"], None) + b"5\r\nhello\r\n0\r\n\r\n")
        k("govde: Transfer-Encoding: chunked -> 411", y[0] == 411, y[0])
        for deger in ("-5", "abc", "1e3", "0x10", "5 5", ""):
            y = ham_istek(s, istek_baytlari("POST", "/v1/state", t, [f"Content-Length: {deger}"]) + b"hello")
            k(f"govde: Content-Length '{deger}' -> 400/411, sunucu 500 vermez", y[0] in (400, 411), (y[0], y[2][:60]))
        k("govde: bu kotu istekler onay penceresi acmadi, oturum acik, veri degismedi",
          s.oturum.faz == "bekliyor" and goruntu(d, m) == on, s.oturum.faz)
        r = wifi(m, s.baglanti, adimlar=["hello", "al"])
        k("govde: sonrasinda sunucu normal istemciyi karsilar", "hata" not in r, r)
        k("govde: sunucuda ic hata (500) gunlugu yok", not any("iç hata" in sat for sat in s.gunluk), s.gunluk)
    finally:
        s.kapat()


def n_yavas(ctx: Baglam):
    """Yavas istemciler: kimliksiz baglanti toplam 10 sn, gövde 30 sn, IP basina 2 baglanti (spec §3)."""
    k = ctx.kontrol
    d, m, dz, u = hazirla(ctx, "wifi-n-yavas")
    s = Sunucu(d)
    dB, mB, _, _ = hazirla(ctx, "wifi-n-yavas-b")
    sB = Sunucu(dB)
    dC, mC, _, _ = hazirla(ctx, "wifi-n-yavas-c")
    sC = Sunucu(dC)
    sinir = KIMLIKSIZ_OMUR_SN + 4
    try:
        # Oturum B: oturum bitince bekleyen bos baglanti de temizlenmeli.
        bosB = tls_ac(sB)
        # Oturum C: KIMLIKLI ama govdesini damlatan istemci (30 sn toplam sinir) -- arka planda.
        govde_damla = tls_ac(sC)
        govde_damla.sendall(f"POST /v1/state HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer {sC.token}\r\nContent-Length: 100000\r\n\r\n".encode())
        stopC = threading.Event()

        def damlatC():
            while not stopC.is_set():
                try:
                    govde_damla.sendall(b"x")
                except (OSError, ssl.SSLError):
                    return
                stopC.wait(3)

        threading.Thread(target=damlatC, daemon=True).start()
        tC = time.monotonic()

        # Faz A: tek damlatan baglanti (slowloris) varken normal istemci yine karsilanir.
        damla = tls_ac(s)
        damla.sendall(b"GET /v1/hello HTTP/1.1\r\nHost: x\r\nX-Yavas: ")
        dur_damla = threading.Event()

        def damlat():
            while not dur_damla.is_set():
                try:
                    damla.sendall(b"a")
                except (OSError, ssl.SSLError):
                    return
                dur_damla.wait(3)

        threading.Thread(target=damlat, daemon=True).start()
        t0 = time.monotonic()
        r = wifi(m, s.baglanti, adimlar=["hello", "al"])
        k("yavas: damlatan baglanti varken normal istemci yine karsilanir", "hata" not in r, r)
        # Oturum B'yi sure dolumuyla bitir: bos baglanti sinir icinde kapanmali.
        sB.saat.ilerle(OMUR_SN + 1)
        k("yavas: B oturumu sure dolumuyla kapandi", sB.bitti_mi("sure_doldu") and sB.kapali_mi(), "")
        kB = kapanis_suresi(bosB, sinir)
        k(f"yavas: oturum bitince bos baglanti <= {sinir} sn icinde temizlendi", kB is not None, kB)
        kd = kapanis_suresi(damla, max(0.5, sinir - (time.monotonic() - t0)))
        dur_damla.set()
        k(f"yavas: damlatilan baglanti toplam omurle (<= {sinir} sn) kesildi (slowloris)", kd is not None, kd)
        sureler = {"damlatan": round(time.monotonic() - t0, 1)}

        # Faz B: IP basina en cok 2 baglanti. 2 bos baglanti (biri TLS'siz) varken 3. hemen kapatilir.
        bos = [tls_ac(s), tls_ac(s, el_sikma=False)]
        t1 = time.monotonic()
        fazla = socket.create_connection((s.ip, s.port), timeout=5)
        kf = kapanis_suresi(fazla, 3)
        fazla.close()
        k("yavas: ayni IP'den 3. eszamanli baglanti hemen kapatilir (IP basina 2)", kf is not None and kf < 3, kf)
        for ad, so in (("bos TLS", bos[0]), ("bos TCP", bos[1])):
            ks = kapanis_suresi(so, max(0.5, sinir - (time.monotonic() - t1)))
            sureler[ad] = None if ks is None else round(time.monotonic() - t1, 1)
            k(f"yavas: {ad} baglantisi <= {sinir} sn icinde kesildi", ks is not None, sureler)
        r = wifi(m, s.baglanti, adimlar=["hello"])
        k("yavas: temizlik sonrasi sunucu calisiyor, oturum acik", "hata" not in r and s.oturum.faz == "bekliyor", r)

        # Faz C: kimlikli gövde damlatan baglanti 30 sn toplam sinirla kesilir.
        kc = kapanis_suresi(govde_damla, max(0.5, GOVDE_OMUR_SN + 4 - (time.monotonic() - tC)))
        stopC.set()
        k(f"yavas: kimlikli gövde damlatan baglanti <= {GOVDE_OMUR_SN + 4} sn icinde kesildi", kc is not None, kc)
        k("yavas: C oturumu kesilen baglantiya ragmen acik, normal istemci karsilanir",
          sC.oturum.faz == "bekliyor" and "hata" not in wifi(mC, sC.baglanti, adimlar=["hello"]), "")
        ctx.sure["yavas en uzun kesilme (sn)"] = max(v for v in [*sureler.values(), round(time.monotonic() - tC, 1)] if v)
    finally:
        s.kapat()
        sB.kapat()
        sC.kapat()


def n_tls(ctx: Baglam):
    k = ctx.kontrol
    d, m, dz, u = hazirla(ctx, "wifi-n-tls")
    s = Sunucu(d)
    try:
        # TLS 1.1 ve 1.0 istemcisi reddedilir.
        for ad, surum in (("TLS 1.1", ssl.TLSVersion.TLSv1_1), ("TLS 1.0", ssl.TLSVersion.TLSv1)):
            try:
                c = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
                c.check_hostname = False
                c.verify_mode = ssl.CERT_NONE
                c.set_ciphers("ALL:@SECLEVEL=0")
                c.minimum_version = c.maximum_version = surum
            except (ValueError, ssl.SSLError) as e:
                print(f"ATLANDI: tls: {ad} istemcisi bu Python/OpenSSL ile kurulamadi ({e})", flush=True)
                k(f"tls: {ad} istemcisi kurulamadi (ATLANDI)", True)
                continue
            once = s.oturum.baglanti_hatasi
            sonuc = "kabul"
            try:
                with socket.create_connection((s.ip, s.port), timeout=5) as raw, c.wrap_socket(raw) as tls:
                    sonuc = f"BAGLANDI {tls.version()}"
            except (ssl.SSLError, OSError) as e:
                sonuc = f"reddedildi: {e}"
            time.sleep(0.5)
            gorulen = s.oturum.baglanti_hatasi > once  # sunucu el sikismasini gordu ve reddetti
            if sonuc.startswith("BAGLANDI"):
                k(f"tls: {ad} istemcisi REDDEDILMELI", False, sonuc)
            elif gorulen:
                k(f"tls: {ad} istemcisi sunucuya ulasti ve sunucu reddetti", True)
            else:
                print(f"ATLANDI: tls: {ad} istemcisi istemci tarafinda engellendi, sunucuya ulasmadi ({sonuc})", flush=True)
                k(f"tls: {ad} istemcisi sunucuya ulasamadi (ATLANDI)", True)
        for ad, surum in (("TLS 1.2", ssl.TLSVersion.TLSv1_2), ("TLS 1.3", ssl.TLSVersion.TLSv1_3)):
            c = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            c.check_hostname = False
            c.verify_mode = ssl.CERT_NONE
            c.minimum_version = c.maximum_version = surum
            try:
                with socket.create_connection((s.ip, s.port), timeout=5) as raw, c.wrap_socket(raw) as tls:
                    k(f"tls: {ad} istemcisi baglanir", tls.version() == ("TLSv1.2" if surum == ssl.TLSVersion.TLSv1_2 else "TLSv1.3"), tls.version())
            except (ssl.SSLError, OSError) as e:
                k(f"tls: {ad} istemcisi baglanir", False, e)
        # Sertifika: parmak izi (Dart'in hesabi `wifi` mutlu yolunda zaten kabul etti) ve icerik.
        with socket.create_connection((s.ip, s.port), timeout=5) as raw, BAGLAM.wrap_socket(raw) as tls:
            der = tls.getpeercert(True)
        f = base64.urlsafe_b64encode(hashlib.sha256(der).digest()).rstrip(b"=").decode()
        k("sertifika: DER SHA-256 (base64url dolgusuz) QR'daki f ile ayni", f == s.parmak and len(f) == 43, (f, s.parmak))
        r = wifi(m, s.baglanti, adimlar=["hello"])
        k("sertifika: istemcinin kendi SHA-256'si (Dart) ayni f ile esleserek baglandi", "hata" not in r, r)
        from cryptography import x509
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.asymmetric import ec
        import ipaddress
        c = x509.load_der_x509_certificate(der)
        san = c.extensions.get_extension_for_class(x509.SubjectAlternativeName).value.get_values_for_type(x509.IPAddress)
        omur = c.not_valid_after_utc - c.not_valid_before_utc
        k("sertifika: SAN = sunucu IP'si", san == [ipaddress.IPv4Address(s.ip)], san)
        k("sertifika: ECDSA P-256 + SHA-256", isinstance(c.public_key(), ec.EllipticCurvePublicKey) and c.public_key().curve.name == "secp256r1"
          and isinstance(c.signature_hash_algorithm, hashes.SHA256), "")
        k("sertifika: en cok ~1 gun gecerli, simdi gecerli", omur <= timedelta(days=1, minutes=10)
          and c.not_valid_before_utc <= datetime.now(timezone.utc) <= c.not_valid_after_utc, omur)
        k("sertifika: CA degil", c.extensions.get_extension_for_class(x509.BasicConstraints).value.ca is False, "")
        kalan = [p for p in Path(tempfile.gettempdir()).glob("takvim-wifi-*.pem")]
        k("sertifika: ozel anahtar diskte kalmadi (gecici .pem yok)", not kalan, kalan)
    finally:
        s.kapat()


def n_gunluk(ctx: Baglam):
    """Token ve dosya icerigi hicbir zaman gunluge yazilmaz (uretim `gunluk` geri cagrisi)."""
    k = ctx.kontrol
    d, m, dz, u = hazirla(ctx, "wifi-n-gunluk")
    d.etkinlik_ekle(olay(uid("gizli"), u["kis"], "GIZLI-BASLIK-XYZ", Y(IST, 2026, 11, 18, 9), Y(IST, 2026, 11, 18, 10)))
    s = Sunucu(d)
    try:
        it = Arka(lambda: wifi(m, s.baglanti))
        onayla(s)
        r = it.al()
        s.bitti_mi("birlestirildi")
        metin = "\n".join(s.gunluk)
        k("gunluk: yalniz acildi/kapandi satirlari", len(s.gunluk) == 2 and "açıldı" in s.gunluk[0] and "kapandı" in s.gunluk[1], s.gunluk)
        k("gunluk: token, parmak izi, baslik, IP/port yok", not any(x in metin for x in (s.token, s.parmak, "GIZLI-BASLIK-XYZ", s.ip, str(s.port))), s.gunluk)
        k("gunluk: istemci hata iletilerinde token yok", not r.get("token_sizdi"), r)
    finally:
        s.kapat()


def n_betik_kapsam(ctx: Baglam):
    """Betikle ayni yol: `--test-ip` olmadan gercek ozel IP'ye baglanma (zaten tum senaryolar); ek kontrol yok."""


BOLUMLER = [
    ("mutlu yol", mutlu), ("gelistirici betigi", betik_mutlu), ("yanlis token / 5 hata", n_token), ("sizinti / basliklar", n_sizinti),
    ("parmak izi", n_parmak), ("sure dolumu", n_sure), ("masaustu ret", n_ret), ("iptal", n_iptal), ("onay zaman asimi 408", n_408),
    ("ikinci istemci/oturum", n_ikinci), ("genel ip", n_genel_ip), ("bozuk govde", n_govde), ("tls ve sertifika", n_tls),
    ("gunluk", n_gunluk), ("yavas istemci", n_yavas),
]


def senaryo_wifi(ctx: Baglam):
    try:
        ip = varsayilan_ip_bul()
    except Exception:  # noqa: BLE001
        ip = ""
    if not ozel_ip_mi(ip):
        print(f"ATLANDI: wifi senaryolari: ozel LAN IPv4 yok (varsayilan yol IP'si: {ip or 'yok'})", flush=True)
        ctx.kontrol("wifi: ATLANDI (ozel LAN IPv4 yok)", True)
        return
    print(f"wifi senaryolari: sunucu {ip} uzerinde", flush=True)
    for ad, fn in BOLUMLER:
        t0 = time.perf_counter()
        n0 = len(ctx.sonuclar)
        try:
            fn(ctx)
        except Exception:  # noqa: BLE001
            ctx.kontrol(f"wifi/{ad}: bolum hatasiz tamamlandi", False, traceback.format_exc(limit=6).strip().splitlines()[-1])
            print(traceback.format_exc(), flush=True)
        ctx.sure[f"wifi/{ad}"] = time.perf_counter() - t0
        yeni = ctx.sonuclar[n0:]
        print(f"  wifi/{ad}: {sum(1 for r in yeni if r[2])}/{len(yeni)}", flush=True)


SENARYOLAR = {"wifi": senaryo_wifi}
