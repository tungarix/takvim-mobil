"""E2E senaryolari: masaustu <-> mobil, iki yonde, yalnizca `.takvimsync` dosyalariyla.

Her senaryo `ctx.kontrol(ad, kosul, detay)` ile tek tek denetim kaydeder. Ortak
olcut: iki cihazin dosya olarak disa aktarilan tam durumu (takvim/etkinlik/gorev
uid kumeleri + butun alanlar + silinenler) ve tekrar acilimi (pencere pencere) ESIT.
"""

from __future__ import annotations

import json
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

from cihazlar import (
    Masaustu, Mobil, Reddedildi, canli, degisiklik, durum, fark, gonder, olusum_farki, oku, simdi, z,
)
from core import from_wall_clock

IST, NY = "Europe/Istanbul", "America/New_York"
PENCERE = ("2026-01-01T00:00:00Z", "2027-07-01T00:00:00Z")
DAR_PENCERELER = [
    ("2026-03-06T00:00:00Z", "2026-03-12T00:00:00Z"),  # ABD ileri saat
    ("2026-03-27T00:00:00Z", "2026-04-02T00:00:00Z"),  # Avrupa ileri saat
    ("2026-10-24T00:00:00Z", "2026-11-04T00:00:00Z"),  # Avrupa + ABD geri saat
    ("2026-09-26T00:00:00Z", "2026-10-06T00:00:00Z"),  # Yeni Zelanda/Sidney ileri saat
]


def Y(tzid: str, *a) -> str:
    """Yerel duvar saatinden UTC metni."""
    return z(from_wall_clock(datetime(*a), tzid))


def olay(uid: str, takvim: str, baslik: str, bas: str, bit: str, tzid: str = IST, **kw) -> dict:
    return {
        "uid": uid, "calendar_uid": takvim, "title": baslik, "description": None, "location": None,
        "start_utc": bas, "end_utc": bit, "tzid": tzid, "all_day": False, "rrule": None,
        "rdate": [], "exdate": [], "reminders": [], "overrides": [],
        "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z", **kw,
    }


def ov(orijinal: str, iptal: bool = False, bas=None, bit=None, baslik=None, yer=None) -> dict:
    return {
        "original_start_utc": orijinal, "cancelled": iptal, "new_start_utc": bas, "new_end_utc": bit,
        "new_title": baslik, "new_location": yer,
    }


_adlar: dict[str, int] = {}


def _n(ad: str) -> int:
    """Dosya adlarinda kullanmak icin kararli kisa numara."""
    return _adlar.setdefault(ad, len(_adlar))


def uid(ad: str) -> str:
    return f"{ad}@takvim.local"


class Baglam:
    """Senaryolara verilen ortak nesne: sunucu, gecici dizinler, denetim kaydi."""

    def __init__(self, sunucu, kok: Path) -> None:
        self.sunucu, self.kok, self.sonuclar, self.senaryo = sunucu, kok, [], ""
        self.sure: dict[str, float] = {}
        self._cihazlar: list = []

    def dizin(self, ad: str) -> Path:
        p = self.kok / ad
        p.mkdir(parents=True, exist_ok=True)
        return p

    def cift(self, ad: str):
        dz = self.dizin(ad)
        d, m = Masaustu(dz), Mobil(self.sunucu, ad.replace("/", "-") + "-mobil", dz)
        self._cihazlar.append(d)
        return d, m, dz

    def kapat(self) -> None:
        for c in self._cihazlar:
            c.kapat()
        self._cihazlar.clear()

    def kontrol(self, ad: str, kosul: bool, detay=""):
        if isinstance(detay, list):
            detay = "; ".join(str(x) for x in detay[:6])
        self.sonuclar.append((self.senaryo, ad, bool(kosul), "" if kosul else str(detay)))

    def esit(self, d, m, dz: Path, etiket: str, pencereler=None):
        """Durum + tekrar acilimi esitligi. Durum sozluklerini dondurur."""
        sd, sm = durum(d, dz), durum(m, dz)
        self.kontrol(f"{etiket}: durum esit", sd == sm, fark(sd, sm, d.ad, m.ad))
        for bas, bit in (pencereler or [PENCERE]):
            f = olusum_farki(d.acilim(bas, bit), m.acilim(bas, bit), d.ad, m.ad)
            self.kontrol(f"{etiket}: acilim esit [{bas[:10]}..{bit[:10]}]", not f, f)
        return sd, sm

    def esitle(self, a, b, dz: Path, etiket: str, azami: int = 4):
        """a->b, b->a turlari yakinsayana kadar. Ilk turdan sonra CANLI veri esit olmali."""
        ilk = [gonder(a, b, dz), gonder(b, a, dz)]
        sa, sb = durum(a, dz), durum(b, dz)
        self.kontrol(f"{etiket}: ilk turdan sonra canli veri esit", canli(sa) == canli(sb), fark(canli(sa), canli(sb), a.ad, b.ad))
        turlar = 1
        while turlar < azami and (degisiklik(ilk[-1]) or degisiklik(ilk[-2])):
            ilk += [gonder(a, b, dz), gonder(b, a, dz)]
            turlar += 1
        self.kontrol(f"{etiket}: {azami} turda yakinsadi (son tur 0 degisiklik)",
                     degisiklik(ilk[-1]) == 0 and degisiklik(ilk[-2]) == 0, f"son raporlar {ilk[-2:]}")
        return turlar


# ============================================================ taban veri (b, d)


def taban(ctx: Baglam, ad: str):
    """Senkron kurulmus bir cift. Ortak taban dosyasi bir saat GERIDEN damgalidir: gercek
    saatle yapilan masaustu degisiklikleri (ayni saniyede kalip 'esitlikte kayit yasar'
    kuralina takilmasin) ve mobilin +-600 sn ofsetli degisiklikleri tabandan kesin yenidir."""
    d, m, dz = ctx.cift(ad)
    u = {"kis": "taban-kisisel", "sil": "taban-silinecek", "E": uid("E"), "S": uid("S"), "Se": uid("Se"),
         "G": uid("G"), "H": uid("H")}
    eski = z(simdi(-3600))
    ev = [
        olay(u["E"], u["kis"], "Tek etkinlik", Y(IST, 2026, 11, 3, 10), Y(IST, 2026, 11, 3, 11), location="Yer"),
        olay(u["S"], u["kis"], "Seri", Y(IST, 2026, 11, 2, 9), Y(IST, 2026, 11, 2, 10), rrule="FREQ=WEEKLY;BYDAY=MO",
             reminders=[10], overrides=[ov(Y(IST, 2026, 11, 9, 9), iptal=True)]),
        olay(u["Se"], u["sil"], "Silinecek takvimdeki", Y(IST, 2026, 11, 4, 10), Y(IST, 2026, 11, 4, 11)),
    ]
    for e in ev:
        e["created_at"] = e["updated_at"] = eski
    gorev = lambda g, b, n=None: {"uid": g, "title": b, "notes": n, "plan_day": None, "event_uid": None, "done_at": None,  # noqa: E731
                                   "created_at": eski, "updated_at": eski}
    dosya = {
        "format": "takvim-sync", "version": 1, "created_at": eski, "device": {"id": "taban", "name": "taban", "app": "e2e"},
        "calendars": [{"uid": u["kis"], "name": "Kişisel", "color": "#3b82f6", "visible": True, "updated_at": eski},
                      {"uid": u["sil"], "name": "Silinecek", "color": "#22c55e", "visible": True, "updated_at": eski}],
        "events": ev, "tasks": [gorev(u["G"], "Görev G", "not"), gorev(u["H"], "Görev H")], "deleted": [],
    }
    yol = dz / "taban.takvimsync"
    yol.write_text(json.dumps(dosya, ensure_ascii=False), encoding="utf-8")
    d.ice(yol)
    m.ice(yol)
    return d, m, dz, u


# ================================================================= senaryo a


def senaryo_a(ctx: Baglam):
    """Masaustunde basla -> mobil -> mobilde duzenle/sil/ekle -> masaustu -> esit."""
    d, m, dz = ctx.cift("a")
    kis, ders = d.takvim_ekle("Kişisel", "#3b82f6"), d.takvim_ekle("Ders", "#ef4444")
    hafta, tek, tum, ny, silinecek = (uid(x) for x in ("hafta", "tek", "tum", "ny", "silinecek"))
    d.etkinlik_ekle(olay(hafta, kis, "Haftalık toplantı", Y(IST, 2026, 11, 2, 10), Y(IST, 2026, 11, 2, 11),
                         rrule="FREQ=WEEKLY;BYDAY=MO", reminders=[10, 60], location="Oda 1",
                         overrides=[ov(Y(IST, 2026, 11, 9, 10), iptal=True),
                                    ov(Y(IST, 2026, 11, 16, 10), bas=Y(IST, 2026, 11, 16, 12), bit=Y(IST, 2026, 11, 16, 13),
                                       baslik="Taşındı 🚀", yer="Kafe")]))
    d.etkinlik_ekle(olay(tek, kis, "Tek", Y(IST, 2026, 11, 5, 14), Y(IST, 2026, 11, 5, 15), description="açıklama"))
    d.etkinlik_ekle(olay(tum, ders, "Sınav günü", Y(IST, 2026, 11, 20), Y(IST, 2026, 11, 21), all_day=True))
    d.etkinlik_ekle(olay(ny, ders, "NY haftalık", Y(NY, 2026, 10, 20, 9), Y(NY, 2026, 10, 20, 10), NY,
                         rrule="FREQ=WEEKLY;BYDAY=TU", exdate=[Y(NY, 2026, 10, 27, 9)], reminders=[15]))
    d.etkinlik_ekle(olay(silinecek, kis, "Silinecek", Y(IST, 2026, 11, 6, 8), Y(IST, 2026, 11, 6, 9)))
    g = {n: uid(n) for n in ("g1", "g2", "g3", "g4", "g5")}
    d.gorev_ekle(g["g1"], "Rapor yaz", "ayrıntılar")
    d.gorev_ekle(g["g2"], "Gün planlı")
    d.gorev_gun(g["g2"], "2026-11-05")
    d.gorev_ekle(g["g3"], "Saat planlı görev", "blok")
    d.gorev_saat(g["g3"], Y(IST, 2026, 11, 9, 14), Y(IST, 2026, 11, 9, 15, 30), kis, IST)
    d.gorev_ekle(g["g4"], "Bitmiş")
    d.gorev_tamamla(g["g4"])
    d.gorev_ekle(g["g5"], "Mobilde bitecek")
    r = gonder(d, m, dz)
    ctx.kontrol("a: masaustu->mobil rapor (takvim 2, atlanan 0)", r["calendar"]["added"] == 2 and r["skipped"] == 0, r)
    ctx.esit(d, m, dz, "a1 masaustu->mobil", [PENCERE] + DAR_PENCERELER)

    # --- mobilde degisiklikler (mobil saati masaustunden SONRA)
    m.ofset(600)
    m.etkinlik_duzenle(tek, title="Mobilde düzenlendi", description="yeni açıklama", location="Mobil ofis",
                       start_utc=Y(IST, 2026, 11, 5, 16), end_utc=Y(IST, 2026, 11, 5, 17))
    m.override_koy(hafta, ov(Y(IST, 2026, 11, 23, 10), iptal=True))
    m.hatirlatici_ekle(hafta, 5)
    m.hatirlatici_sil(hafta, 60)
    m.gorev_tamamla(g["g5"])
    m.etkinlik_sil(silinecek)
    m.gorev_sil(g["g1"])
    m.takvim_duzenle(ders, visible=False)
    m.gorev_saat(g["g3"], Y(IST, 2026, 11, 10, 9), Y(IST, 2026, 11, 10, 10), kis, IST)
    blok = next(t["event_uid"] for t in durum(m, dz)["tasks"] if t["uid"] == g["g3"])
    m.etkinlik_duzenle(blok, title="Blok adı mobilde değişti")  # blok adı göreve de yansımalı
    mobil_cal = m.takvim_ekle("Mobil Takvim", "#a855f7")
    m.etkinlik_ekle(olay(uid("mobil-aylik"), mobil_cal, "Aylık (mobil)", Y(IST, 2026, 11, 12, 18), Y(IST, 2026, 11, 12, 19),
                         rrule="FREQ=MONTHLY;BYMONTHDAY=12", reminders=[30]))
    m.etkinlik_ekle(olay(uid("mobil-tek"), kis, "Mobil tek 😀", Y(IST, 2026, 11, 13, 9), Y(IST, 2026, 11, 13, 10)))
    m.gorev_ekle(uid("g6"), "Mobil görev", "mobilde eklendi")
    m.gorev_gun(uid("g6"), "2026-11-14")
    r = gonder(m, d, dz)
    ctx.kontrol("a: mobil->masaustu rapor (silinen >= 2, eklenen takvim 1)", r["deleted"] >= 2 and r["calendar"]["added"] == 1, r)
    sd, sm = ctx.esit(d, m, dz, "a2 mobil->masaustu", [PENCERE] + DAR_PENCERELER)
    ev = {e["uid"]: e for e in sd["events"]}
    gv = {t["uid"]: t for t in sd["tasks"]}
    ctx.kontrol("a: duzenleme masaustune ulasti", ev[tek]["title"] == "Mobilde düzenlendi" and ev[tek]["location"] == "Mobil ofis"
                and ev[tek]["start_utc"] == Y(IST, 2026, 11, 5, 16), ev[tek])
    ctx.kontrol("a: hatirlatici/override masaustune ulasti", ev[hafta]["reminders"] == [5, 10]
                and len(ev[hafta]["overrides"]) == 3, ev[hafta]["reminders"])
    ctx.kontrol("a: gorev tamamlandi/silindi/yeni", gv[g["g5"]]["done_at"] is not None and g["g1"] not in gv and uid("g6") in gv, "")
    ctx.kontrol("a: silinen etkinlik gitti, mezar tasi var", silinecek not in ev
                and any(x["kind"] == "event" and x["uid"] == silinecek for x in sd["deleted"]), "")
    ctx.kontrol("a: yeni takvim + etkinlikler", any(c["name"] == "Mobil Takvim" for c in sd["calendars"])
                and uid("mobil-aylik") in ev and uid("mobil-tek") in ev, "")
    ctx.kontrol("a: takvim gorunurlugu", [c["visible"] for c in sd["calendars"] if c["uid"] == ders] == [False], "")
    ctx.kontrol("a: saat planli gorev blogu tasindi", ev[blok]["start_utc"] == Y(IST, 2026, 11, 10, 9), ev.get(blok))
    ctx.kontrol("a: blok adi gorev basligina yansidi", gv[g["g3"]]["title"] == "Blok adı mobilde değişti", gv[g["g3"]]["title"])

    # --- masaustunde ikinci dalga (mobilde dokunulmayan kayitlar) -> mobile geri
    time.sleep(1.1)  # silme/duzenleme, kaydin kendi saniyesinden KESIN yeni olsun
    d.override_koy(ny, ov(Y(NY, 2026, 11, 3, 9), baslik="NY ozel"))
    d.etkinlik_duzenle(ny, title="NY haftalık (düzenlendi)")
    d.gorev_sil(g["g2"])
    d.etkinlik_ekle(olay(uid("masa-yeni"), mobil_cal, "Masaüstünden mobil takvime", Y(IST, 2026, 11, 15, 10), Y(IST, 2026, 11, 15, 11)))
    d.gorev_ekle(uid("g7"), "Masaüstü görev")
    r = gonder(d, m, dz)
    ctx.kontrol("a: masaustu->mobil ikinci dalga", r["event"]["added"] == 1 and r["event"]["updated"] == 1 and r["task"]["deleted"] == 1, r)
    ctx.esit(d, m, dz, "a3 geri aktarim", [PENCERE] + DAR_PENCERELER)
    r1, r2 = gonder(m, d, dz), gonder(d, m, dz)
    ctx.kontrol("a: yankisiz (son iki aktarim 0 degisiklik)", degisiklik(r1) == 0 and degisiklik(r2) == 0, (r1, r2))
    ctx.esit(d, m, dz, "a4 son", [PENCERE])


# ================================================================= senaryo b


def _lww(ctx: Baglam, mobil_sonra: bool, sira: str):
    et = f"b-lww {'mobil sonra' if mobil_sonra else 'masaustu sonra'} {sira}"
    d, m, dz, u = taban(ctx, f"b-lww-{int(mobil_sonra)}-{sira}")
    d.etkinlik_duzenle(u["E"], title="D baslik", location="Masaustu yeri")
    d.gorev_tamamla(u["G"])
    d.override_koy(u["S"], ov(Y(IST, 2026, 11, 16, 9), iptal=True))
    d.takvim_duzenle(u["kis"], name="Masaüstü Kişisel", color="#111111")
    d.gorev_guncelle(u["H"], title="H masaustu")
    m.ofset(600 if mobil_sonra else -600)
    m.etkinlik_duzenle(u["E"], title="M baslik", description="mobil aciklama")
    m.gorev_guncelle(u["G"], title="G mobil")
    m.hatirlatici_ekle(u["S"], 5)
    m.takvim_duzenle(u["kis"], name="Mobil Kişisel")
    m.gorev_guncelle(u["H"], title="H mobil")
    a, b = (d, m) if sira == "dm" else (m, d)
    ctx.esitle(a, b, dz, et)
    sd, sm = ctx.esit(d, m, dz, et)
    kazan = "M" if mobil_sonra else "D"
    ev = {e["uid"]: e for e in sd["events"]}
    gv = {t["uid"]: t for t in sd["tasks"]}
    cv = {c["uid"]: c for c in sd["calendars"]}
    ctx.kontrol(f"{et}: etkinlik sonraki yazana ait", ev[u["E"]]["title"] == f"{kazan} baslik", ev[u["E"]]["title"])
    ctx.kontrol(f"{et}: gorev kayit duzeyinde (G)", (gv[u["G"]]["title"], gv[u["G"]]["done_at"] is not None)
                == (("G mobil", False) if mobil_sonra else ("Görev G", True)), gv[u["G"]])
    ctx.kontrol(f"{et}: seri tek birim (override+hatirlatici birlikte)",
                (ev[u["S"]]["reminders"], len(ev[u["S"]]["overrides"])) == (([5, 10], 1) if mobil_sonra else ([10], 2)),
                (ev[u["S"]]["reminders"], len(ev[u["S"]]["overrides"])))
    ctx.kontrol(f"{et}: takvim adi", cv[u["kis"]]["name"] == ("Mobil Kişisel" if mobil_sonra else "Masaüstü Kişisel"), cv[u["kis"]])
    ctx.kontrol(f"{et}: gorev H", gv[u["H"]]["title"] == ("H mobil" if mobil_sonra else "H masaustu"), gv[u["H"]]["title"])


def _sil_duzenle(ctx: Baglam, silen_mobil: bool, duzenleme_sonra: bool, sira: str, tur: str):
    et = f"b-sil {tur} {'mobil' if silen_mobil else 'masaustu'} siler, duzenleme {'sonra' if duzenleme_sonra else 'once'} {sira}"
    d, m, dz, u = taban(ctx, f"b-sil-{tur}-{int(silen_mobil)}-{int(duzenleme_sonra)}-{sira}")
    hedef = u["E"] if tur == "etkinlik" else u["G"]
    silen, duzenleyen = (m, d) if silen_mobil else (d, m)
    if silen_mobil:  # mobil siler: duzenleme (masaustu, gercek saat) sonra ise silme ESKI olmali
        m.ofset(-600 if duzenleme_sonra else 600)
    else:  # masaustu siler (gercek saat): duzenleme (mobil) sonra ise ofset +
        m.ofset(600 if duzenleme_sonra else -600)
    if tur == "etkinlik":
        silen.etkinlik_sil(hedef)
        duzenleyen.etkinlik_duzenle(hedef, title="Duzenlendi")
    else:
        silen.gorev_sil(hedef)
        duzenleyen.gorev_guncelle(hedef, title="Duzenlendi")
    a, b = (d, m) if sira == "dm" else (m, d)
    ctx.esitle(a, b, dz, et)
    sd, _ = ctx.esit(d, m, dz, et)
    liste = sd["events"] if tur == "etkinlik" else sd["tasks"]
    var = [r for r in liste if r["uid"] == hedef]
    mezar = [x for x in sd["deleted"] if x["uid"] == hedef]
    ctx.kontrol(f"{et}: {'kayit yasar' if duzenleme_sonra else 'silme kazanir'}",
                bool(var) == duzenleme_sonra and bool(mezar) != duzenleme_sonra,
                f"kayit={bool(var)} mezar={bool(mezar)}")
    if var:
        ctx.kontrol(f"{et}: duzenleme korundu", var[0]["title"] == "Duzenlendi", var[0]["title"])


def _takvim_silme(ctx: Baglam):
    # 1) mobil takvimi SONRA siler, masaustu icindeki etkinligi duzenlemisti -> hepsi gider
    d, m, dz, u = taban(ctx, "b-takvim-1")
    d.etkinlik_duzenle(u["Se"], title="Masaustu duzenledi")
    m.ofset(600)
    m.takvim_sil(u["sil"])
    ctx.esitle(d, m, dz, "b-takvim mobil siler (sonra)")
    sd, _ = ctx.esit(d, m, dz, "b-takvim mobil siler (sonra)")
    ctx.kontrol("b-takvim: takvim ve etkinlik gitti, mezar tasi ikisinde de",
                u["sil"] not in {c["uid"] for c in sd["calendars"]} and u["Se"] not in {e["uid"] for e in sd["events"]}
                and {("calendar", u["sil"]), ("event", u["Se"])} <= {(x["kind"], x["uid"]) for x in sd["deleted"]}, "")
    # 2) masaustu takvimi siler (CASCADE), mobil etkinligi SONRA duzenlemisti -> etkinlik yetim kalir, takvimle gider
    d, m, dz, u = taban(ctx, "b-takvim-2")
    d.takvim_sil(u["sil"])
    m.ofset(600)
    m.etkinlik_duzenle(u["Se"], title="Mobil sonra duzenledi")
    ctx.esitle(d, m, dz, "b-takvim masaustu siler, etkinlik sonra duzenlendi")
    sd, _ = ctx.esit(d, m, dz, "b-takvim masaustu siler, etkinlik sonra duzenlendi")
    ctx.kontrol("b-takvim: yetim etkinlik takvimle gitti", u["Se"] not in {e["uid"] for e in sd["events"]}, "")
    # 3) mobil takvimi tabandan bile ESKI bir anda siler, masaustu etkinligi duzenlemisti -> etkinlik ve takvim yasar
    d, m, dz, u = taban(ctx, "b-takvim-3")
    d.etkinlik_duzenle(u["Se"], title="Masaustu duzenledi")
    m.ofset(-7200)
    m.takvim_sil(u["sil"])
    ctx.esitle(d, m, dz, "b-takvim eski silme")
    sd, _ = ctx.esit(d, m, dz, "b-takvim eski silme")
    ctx.kontrol("b-takvim: eski silme kayiti oldurmez", u["sil"] in {c["uid"] for c in sd["calendars"]}
                and u["Se"] in {e["uid"] for e in sd["events"]}, "")
    # 4) takvim ad degisikligi sonra, silme once
    d, m, dz, u = taban(ctx, "b-takvim-4")
    m.ofset(-600)
    m.takvim_sil(u["sil"])
    d.takvim_duzenle(u["sil"], name="Yeniden adlandi")
    ctx.esitle(d, m, dz, "b-takvim silme once, ad degisikligi sonra")
    sd, _ = ctx.esit(d, m, dz, "b-takvim silme once, ad degisikligi sonra")
    ctx.kontrol("b-takvim: yeniden adlandirilan takvim yasar", [c["name"] for c in sd["calendars"] if c["uid"] == u["sil"]] == ["Yeniden adlandi"], "")


def _geri_al(ctx: Baglam):
    """Silip geri al (arayuzdeki 'geri al'): kayit iki cihazda da diriliyor, mezar tasi kalkiyor."""
    for kim in ("masaustu", "mobil"):
        d, m, dz, u = taban(ctx, f"b-geri-{kim}")
        silen, diger = (d, m) if kim == "masaustu" else (m, d)
        silen.etkinlik_sil_geri_alinabilir(u["S"])
        r = gonder(silen, diger, dz)
        ctx.kontrol(f"b-geri {kim}: silme karsiya gitti", r["event"]["deleted"] == 1, r)
        silen.geri_al()
        ctx.esitle(d, m, dz, f"b-geri {kim}")
        sd, _ = ctx.esit(d, m, dz, f"b-geri {kim}")
        ctx.kontrol(f"b-geri {kim}: etkinlik her iki cihazda dirildi, mezar tasi yok",
                    u["S"] in {e["uid"] for e in sd["events"]} and not any(x["uid"] == u["S"] for x in sd["deleted"]), "")
        e = next(e for e in sd["events"] if e["uid"] == u["S"])
        ctx.kontrol(f"b-geri {kim}: hatirlatici ve override korundu", e["reminders"] == [10] and len(e["overrides"]) == 1, e)


def senaryo_b(ctx: Baglam):
    """LWW iki yon, duzenle-vs-sil her iki sira, takvim silme, geri al."""
    for sonra in (True, False):
        for sira in ("dm", "md"):
            _lww(ctx, sonra, sira)
    for tur in ("etkinlik", "gorev"):
        for silen_mobil in (False, True):
            for sonra in (False, True):
                for sira in ("dm", "md"):
                    _sil_duzenle(ctx, silen_mobil, sonra, sira, tur)
    _takvim_silme(ctx)
    _geri_al(ctx)


# ================================================================= senaryo c


def senaryo_c(ctx: Baglam):
    """Iki cihazda bagimsiz 'Kisisel' ad eslesmesiyle birlesir, cift takvim olmaz."""
    for varyant, (ad_d, ad_m) in {"ayni": ("Kişisel", "Kişisel"), "kenar bosluk": ("Kişisel", "  Kişisel "),
                                  "buyuk-kucuk": ("Ders", "DERS"), "kucuk": ("Kişisel", "kişisel")}.items():
        for mod in ("sirayla", "ayni anda"):
            et = f"c {varyant} {mod}"
            d, m, dz = ctx.cift(f"c-{varyant}-{mod}".replace(" ", "_"))
            m.ofset(60)  # esit damgada her taraf kendi degerini korur (spec siniri); mobil bir dakika sonra
            ud, um = d.takvim_ekle(ad_d), m.takvim_ekle(ad_m)
            ctx.kontrol(f"{et}: baslangicta uid'ler farkli", ud != um, "")
            d.etkinlik_ekle(olay(uid("ed"), ud, "Masaustu etkinligi", Y(IST, 2026, 11, 3, 10), Y(IST, 2026, 11, 3, 11)))
            m.etkinlik_ekle(olay(uid("em"), um, "Mobil etkinligi", Y(IST, 2026, 11, 4, 10), Y(IST, 2026, 11, 4, 11)))
            d.gorev_ekle(uid("gd"), "masaustu gorevi")
            if mod == "sirayla":
                ctx.esitle(d, m, dz, et)
            else:  # iki dosya birbirinden habersiz, ayni anda uretilir ve capraz iceri aktarilir
                f1, f2 = dz / "capraz-d.takvimsync", dz / "capraz-m.takvimsync"
                d.disa(f1)
                m.disa(f2)
                d.ice(f2)
                m.ice(f1)
                ctx.esitle(d, m, dz, et, azami=5)
            sd, sm = ctx.esit(d, m, dz, et)
            ctx.kontrol(f"{et}: tek takvim", len(sd["calendars"]) == 1 and len(sm["calendars"]) == 1,
                        ([c["name"] for c in sd["calendars"]], [c["name"] for c in sm["calendars"]]))
            cuid = sd["calendars"][0]["uid"]
            ctx.kontrol(f"{et}: iki etkinlik de ayni takvimde, kayip yok",
                        sorted(e["calendar_uid"] for e in sd["events"]) == [cuid, cuid] and len(sm["events"]) == 2, "")
    # farkli adli takvimler birlesmez
    d, m, dz = ctx.cift("c-farkli")
    d.takvim_ekle("Ders")
    m.takvim_ekle("Kişisel")
    ctx.esitle(d, m, dz, "c farkli adlar")
    sd, _ = ctx.esit(d, m, dz, "c farkli adlar")
    ctx.kontrol("c: farkli adli takvimler ikilenmez ve birlesmez", sorted(c["name"] for c in sd["calendars"]) == ["Ders", "Kişisel"], sd["calendars"])
    # ayni adli iki takvim ayni dosyada (masaustunde iki 'Notlar'): dosyanin kendi uid'leri benimsenmez
    d, m, dz = ctx.cift("c-cift-ad")
    m.ofset(60)
    d.takvim_ekle("Notlar", "#111111")
    d.takvim_ekle("Notlar", "#222222")
    m.takvim_ekle("Notlar", "#333333")
    ctx.esitle(d, m, dz, "c iki ayni adli dosya takvimi", azami=5)
    sd, sm = ctx.esit(d, m, dz, "c iki ayni adli dosya takvimi")
    ctx.kontrol("c: ayni adli iki takvim korunur, mobilinki birine eslenir (toplam 2)", len(sd["calendars"]) == 2, sd["calendars"])


# ================================================================= senaryo d


def senaryo_d(ctx: Baglam):
    """Idempotans, ping-pong, silme yankisi."""
    d, m, dz, u = taban(ctx, "d")
    # ayni dosya iki kez
    f = dz / "bir.takvimsync"
    d.disa(f)
    iz_m = m.parmak_izi()
    r1, r2 = m.ice(f), m.ice(f)
    ctx.kontrol("d: ayni dosya mobilde 2 kez: sayaclar 0", degisiklik(r1) == 0 and degisiklik(r2) == 0, (r1, r2))
    ctx.kontrol("d: mobil deposu degismedi", m.parmak_izi() == iz_m, "")
    m.disa(dz / "m.takvimsync")
    iz_d = d.parmak_izi()
    r1, r2 = d.ice(dz / "m.takvimsync"), d.ice(dz / "m.takvimsync")
    ctx.kontrol("d: ayni dosya masaustunde 2 kez: sayaclar 0", degisiklik(r1) == 0 and degisiklik(r2) == 0, (r1, r2))
    ctx.kontrol("d: masaustu veritabani degismedi (id'ler ve sayaclar dahil)", d.parmak_izi() == iz_d, "")
    # temiz cihaza ayni dosya iki kez (mobil + masaustu)
    d2, m2, dz2 = ctx.cift("d-temiz")
    f2 = dz2 / "tam.takvimsync"
    d.disa(f2)
    a1, a2, b1, b2 = d2.ice(f2), d2.ice(f2), m2.ice(f2), m2.ice(f2)
    ctx.kontrol("d: temiz cihaza ilk aktarim ekler, ikinci 0", degisiklik(a1) > 0 and degisiklik(a2) == 0 and degisiklik(b1) > 0 and degisiklik(b2) == 0, (a1, a2, b1, b2))
    ctx.esit(d2, m2, dz2, "d temiz cihazlar esit", [PENCERE])

    # ping-pong: A->B->A->B ... duzenle/sil arasinda
    m.ofset(600)
    m.etkinlik_duzenle(u["E"], title="Mobil duzenledi")
    m.etkinlik_sil(u["S"])
    m.gorev_tamamla(u["G"])
    m.takvim_sil(u["sil"])
    tur = []
    for _ in range(3):
        tur.append((gonder(m, d, dz), gonder(d, m, dz)))
    ctx.kontrol("d: ilk tur gercek degisiklik tasir", degisiklik(tur[0][0]) >= 5, tur[0][0])
    ctx.kontrol("d: ping-pong ikinci turdan sonra hep 0 (silme yankisi yok)",
                all(degisiklik(a) == 0 and degisiklik(b) == 0 for a, b in tur[1:]) and degisiklik(tur[0][1]) == 0, tur)
    sd, sm = ctx.esit(d, m, dz, "d ping-pong sonu")
    ctx.kontrol("d: silmeler mezar tasi olarak her iki cihazda", {("event", u["S"]), ("calendar", u["sil"]), ("event", u["Se"])}
                <= {(x["kind"], x["uid"]) for x in sd["deleted"]}, sd["deleted"])
    # masaustu siler (mobilin dokunmadigi gorev) -> mobil -> geri
    d.gorev_sil(u["H"])
    r_dm = gonder(d, m, dz)
    r_md = gonder(m, d, dz)
    ctx.kontrol("d: masaustu silmesi mobilde 1 silme, geri donusta 0", r_dm["task"]["deleted"] == 1 and degisiklik(r_md) == 0, (r_dm, r_md))
    ctx.esit(d, m, dz, "d masaustu silmesi sonrasi")
    # mezar tasi zamanini dosyadaki ile ayni yazar: iki cihazda ayni deleted_at
    sd, sm = durum(d, dz), durum(m, dz)
    ctx.kontrol("d: mezar tasi zamanlari iki cihazda ayni", sd["deleted"] == sm["deleted"], fark(sd, sm))
    # silinen kaydin ESKI dosyasi geri getirmez
    eski = dz / "eski-tam.takvimsync"
    d2.disa(eski)  # d2: silmelerden onceki tam durum
    ra, rb = d.ice(eski), m.ice(eski)
    ctx.kontrol("d: silmelerden onceki eski dosya silinenleri geri getirmez", degisiklik(ra) == 0 and degisiklik(rb) == 0, (ra, rb))
    ctx.esit(d, m, dz, "d eski dosya sonrasi", [PENCERE])


# ================================================================= senaryo e


TR_METIN = "İstanbul’da Çarşamba toplantısı — şğüöçı İĞÜŞÖÇ 😀🎉 👨‍👩‍👧 é ñ 漢字 ‮  \"tırnak\" \\ ters </script> 'a'"
TR_ACIKLAMA = "Satır 1\r\nSatır 2\n\tgirintili “eğri tırnak” %s &amp; <b>kalın</b> 𝔘𝔫𝔦𝔠𝔬𝔡𝔢 boşluk​"
BUYUK = ("Büyük açıklama ğüşiöç 😀 abcdefghij " * 400)[:10000]


def cesitli(kis: str, ders: str, p: str) -> list[dict]:
    L: list[dict] = []

    def ek(ad, takvim, baslik, bas, bit, tzid=IST, **kw):
        L.append(olay(uid(f"{p}-{ad}"), takvim, baslik, bas, bit, tzid, **kw))

    ek("trk", kis, TR_METIN, Y(IST, 2026, 11, 3, 9), Y(IST, 2026, 11, 3, 10, 30), description=TR_ACIKLAMA, location="Kadıköy 🏠",
       reminders=[0, 5, 10080])
    ek("buyuk", kis, "Büyük açıklama", Y(IST, 2026, 11, 4, 9), Y(IST, 2026, 11, 4, 10), description=BUYUK)
    ek("bos1", ders, "", Y(IST, 2026, 11, 5, 9), Y(IST, 2026, 11, 5, 10))
    ek("bos2", ders, "boş metinler", Y(IST, 2026, 11, 5, 11), Y(IST, 2026, 11, 5, 12), description="", location="")
    ek("ny", kis, "NY haftalık (ABD yaz saati ileri/geri)", Y(NY, 2026, 2, 24, 9), Y(NY, 2026, 2, 24, 10), NY,
       rrule="FREQ=WEEKLY;BYDAY=TU", exdate=[Y(NY, 2026, 3, 10, 9)], reminders=[15])
    ek("ny-ileri", kis, "NY 02:30 (var olmayan saat)", Y(NY, 2026, 3, 6, 2, 30), Y(NY, 2026, 3, 6, 3), NY, rrule="FREQ=DAILY;COUNT=5")
    ek("ny-geri", kis, "NY 01:30 (tekrar eden saat)", Y(NY, 2026, 10, 30, 1, 30), Y(NY, 2026, 10, 30, 2), NY, rrule="FREQ=DAILY;COUNT=5")
    ek("ny-pazar", kis, "NY pazar 02:30", Y(NY, 2026, 2, 22, 2, 30), Y(NY, 2026, 2, 22, 3), NY, rrule="FREQ=WEEKLY;COUNT=6")
    ek("londra", ders, "Londra günlük", Y("Europe/London", 2026, 3, 25, 8, 30), Y("Europe/London", 2026, 3, 25, 9, 30),
       "Europe/London", rrule="FREQ=DAILY;COUNT=10")
    ek("sidney", ders, "Sidney aylık", Y("Australia/Sydney", 2026, 1, 1, 8), Y("Australia/Sydney", 2026, 1, 1, 9),
       "Australia/Sydney", rrule="FREQ=MONTHLY;BYMONTHDAY=1;COUNT=14")
    ek("auckland", ders, "Auckland haftalık", Y("Pacific/Auckland", 2026, 9, 20, 7), Y("Pacific/Auckland", 2026, 9, 20, 8),
       "Pacific/Auckland", rrule="FREQ=WEEKLY;COUNT=40")
    ek("katmandu", kis, "Katmandu (+5:45)", Y("Asia/Kathmandu", 2026, 11, 9, 10), Y("Asia/Kathmandu", 2026, 11, 9, 11), "Asia/Kathmandu")
    ek("kalkuta", kis, "Kalküta haftalık", Y("Asia/Kolkata", 2026, 11, 2, 10), Y("Asia/Kolkata", 2026, 11, 2, 11), "Asia/Kolkata",
       rrule="FREQ=WEEKLY;BYDAY=MO,TH")
    # IANA takma adlari (zoneinfo bilir; mobilin saat dilimi veritabani ayrica bir tabloyla cozer)
    for ad_, tz_ in (("amsterdam", "Europe/Amsterdam"), ("kalkuta-eski", "Asia/Calcutta"), ("abd-dogu", "US/Eastern"),
                     ("gmt", "GMT"), ("etc-utc", "Etc/UTC"), ("kiev", "Europe/Kiev"), ("istanbul-turkey", "Turkey")):
        ek(f"tz-{ad_}", kis, f"Takma ad {tz_}", Y(tz_, 2026, 3, 2, 9), Y(tz_, 2026, 3, 2, 10), tz_, rrule="FREQ=WEEKLY;COUNT=60")
    ek("utc", kis, "UTC", "2026-11-10T10:00:00Z", "2026-11-10T11:00:00Z", "UTC")
    ek("etc", kis, "Etc/GMT+5", "2026-11-11T10:00:00Z", "2026-11-11T11:00:00Z", "Etc/GMT+5", rrule="FREQ=DAILY;COUNT=3")
    ek("aylik31", kis, "Ayın 31'i", Y(IST, 2026, 1, 31, 9), Y(IST, 2026, 1, 31, 10), rrule="FREQ=MONTHLY;BYMONTHDAY=31")
    ek("son-cuma", kis, "Ayın son cuması", Y(IST, 2026, 1, 30, 9), Y(IST, 2026, 1, 30, 10), rrule="FREQ=MONTHLY;BYDAY=FR;BYSETPOS=-1")
    ek("artik", kis, "Artık yıl", Y(IST, 2024, 2, 29, 9), Y(IST, 2024, 2, 29, 10), rrule="FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29")
    ek("until", kis, "UNTIL'li", Y(IST, 2026, 11, 1, 9), Y(IST, 2026, 11, 1, 10), rrule="FREQ=DAILY;UNTIL=20261115T000000Z")
    ek("aralik", kis, "Aralıklı", Y(IST, 2026, 11, 2, 7), Y(IST, 2026, 11, 2, 8, 30), rrule="FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR;COUNT=7")
    ek("rdate", kis, "RDATE'li", Y(IST, 2026, 11, 2, 15), Y(IST, 2026, 11, 2, 16), rrule="FREQ=WEEKLY;COUNT=3",
       rdate=[Y(IST, 2026, 12, 25, 15), Y(IST, 2026, 12, 31, 15)], exdate=[Y(IST, 2026, 11, 9, 15)])
    for i, kural in enumerate([
        "FREQ=WEEKLY;WKST=SU;BYDAY=SU,MO;COUNT=6", "FREQ=MONTHLY;BYDAY=2TU", "FREQ=MONTHLY;BYDAY=-1SU;COUNT=8",
        "FREQ=YEARLY;BYMONTH=9;BYDAY=1MO;COUNT=3", "FREQ=YEARLY;BYWEEKNO=20;BYDAY=MO;COUNT=3",
        "FREQ=YEARLY;BYYEARDAY=100,200;COUNT=4", "FREQ=DAILY;BYHOUR=9,17;COUNT=6", "FREQ=HOURLY;INTERVAL=6;COUNT=8",
        "FREQ=MINUTELY;INTERVAL=90;COUNT=5", "RRULE:FREQ=WEEKLY;COUNT=3", "freq=weekly;count=3",
        "FREQ=DAILY;UNTIL=20261115", "FREQ=DAILY;UNTIL=20261115T120000", "FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=6",
        "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;INTERVAL=2", "FREQ=MONTHLY;INTERVAL=3;BYSETPOS=1;BYDAY=MO,TU,WE,TH,FR",
    ]):
        ek(f"kural{i}", kis, f"Kural {kural[:30]}", Y(IST, 2026, 9, 7, 9), Y(IST, 2026, 9, 7, 10), rrule=kural)
    ek("tum", ders, "Tüm gün (3 gün)", Y(IST, 2026, 11, 3), Y(IST, 2026, 11, 6), all_day=True)
    ek("tum-hafta", ders, "Tüm gün haftalık", Y(IST, 2026, 11, 2), Y(IST, 2026, 11, 3), all_day=True, rrule="FREQ=WEEKLY;COUNT=6")
    ek("tum-ny", ders, "NY tüm gün (49 saat)", Y(NY, 2026, 10, 31), Y(NY, 2026, 11, 2), NY, all_day=True)
    ek("tum-ny-dst", ders, "NY tüm gün günlük DST", Y(NY, 2026, 3, 7), Y(NY, 2026, 3, 8), NY, all_day=True, rrule="FREQ=DAILY;COUNT=4")
    ek("override", kis, "Override'lı", Y(IST, 2026, 11, 2, 18), Y(IST, 2026, 11, 2, 19), rrule="FREQ=DAILY;COUNT=10",
       overrides=[ov(Y(IST, 2026, 11, 3, 18), iptal=True),
                  ov(Y(IST, 2026, 11, 4, 18), bas=Y(IST, 2026, 11, 4, 20), bit=Y(IST, 2026, 11, 4, 22), baslik="Yeni 😀", yer="Yeni yer"),
                  ov(Y(IST, 2026, 11, 5, 18), baslik="Sadece başlık"),
                  ov(Y(IST, 2026, 11, 6, 18), yer="Sadece yer"),
                  ov(Y(IST, 2026, 11, 20, 18), iptal=True)])  # serinin dışındaki bayat override
    ek("override-bitissiz", kis, "Bitişsiz taşıma", Y(IST, 2026, 11, 2, 12), Y(IST, 2026, 11, 2, 13), rrule="FREQ=DAILY;COUNT=4",
       overrides=[ov(Y(IST, 2026, 11, 3, 12), bas=Y(IST, 2026, 11, 3, 14))])
    return L


def cesitli_gorevler(c, kis: str, p: str):
    c.gorev_ekle(uid(f"{p}-g1"), "Görev 😀 İĞÜŞÖÇ", "Uzun not. " * 200)
    c.gorev_ekle(uid(f"{p}-g2"), "Gün planlı")
    c.gorev_gun(uid(f"{p}-g2"), "2026-03-08")
    c.gorev_ekle(uid(f"{p}-g3"), "Bitmiş görev", "   ")  # sadece boşluk notu -> yok
    c.gorev_tamamla(uid(f"{p}-g3"))
    c.gorev_ekle(uid(f"{p}-g4"), "Saat planlı", "blok")
    c.gorev_saat(uid(f"{p}-g4"), Y(NY, 2026, 3, 8, 3, 30), Y(NY, 2026, 3, 8, 4, 30), kis, NY)
    c.gorev_ekle(uid(f"{p}-g5"), "Plansız notsuz")


def senaryo_e(ctx: Baglam):
    """Icerik/zaman dilimi/DST/tum gun/bos alan/buyuk metin; iki yonde."""
    d, m, dz = ctx.cift("e")
    dk, dd = d.takvim_ekle("Kişisel"), d.takvim_ekle("Ders", "#ef4444")
    for e in cesitli(dk, dd, "d"):
        d.etkinlik_ekle(e)
    cesitli_gorevler(d, dk, "d")
    pen = [PENCERE] + DAR_PENCERELER
    ctx.kontrol("e: masaustu->mobil hatasiz", (r := gonder(d, m, dz))["skipped"] == 0 and r["event"]["added"] >= 28, r)
    sd, sm = ctx.esit(d, m, dz, "e1 masaustu->mobil", pen)
    # mobilde bagimsiz olarak ayni cesitliligi yarat (farkli uid'ler) ve geri aktar
    mk = next(c["uid"] for c in sm["calendars"] if c["name"] == "Kişisel")
    md = next(c["uid"] for c in sm["calendars"] if c["name"] == "Ders")
    m.ofset(60)
    for e in cesitli(mk, md, "m"):
        m.etkinlik_ekle(e)
    cesitli_gorevler(m, mk, "m")
    ctx.kontrol("e: mobil->masaustu hatasiz", (r := gonder(m, d, dz))["skipped"] == 0 and r["event"]["added"] >= 28, r)
    sd, sm = ctx.esit(d, m, dz, "e2 mobil->masaustu", pen)
    n = len(d.acilim(*PENCERE))
    ctx.kontrol("e: acilim anlamli sayida (>1000 ornek)", n > 1000, n)
    # alan degerlerini ham dosyada da dogrula (iki taraf da kaybetmeden tasidi)
    ev = {e["uid"]: e for e in sd["events"]}
    for p in ("d", "m"):
        t = ev[uid(f"{p}-trk")]
        ctx.kontrol(f"e: {p} Turkce+emoji baslik/aciklama/yer birebir", t["title"] == TR_METIN and t["description"] == TR_ACIKLAMA
                    and t["location"] == "Kadıköy 🏠", (t["title"][:40], t["description"][:40]))
        ctx.kontrol(f"e: {p} 10 bin karakterlik aciklama birebir", ev[uid(f"{p}-buyuk")]["description"] == BUYUK, "")
        ctx.kontrol(f"e: {p} bos/null alanlar", (ev[uid(f"{p}-bos1")]["title"], ev[uid(f"{p}-bos1")]["description"]) == ("", None)
                    and (ev[uid(f"{p}-bos2")]["description"], ev[uid(f"{p}-bos2")]["location"]) == ("", ""), "")
        ctx.kontrol(f"e: {p} tzid korundu", ev[uid(f"{p}-katmandu")]["tzid"] == "Asia/Kathmandu" and ev[uid(f"{p}-etc")]["tzid"] == "Etc/GMT+5"
                    and ev[uid(f"{p}-tz-kalkuta-eski")]["tzid"] == "Asia/Calcutta" and ev[uid(f"{p}-utc")]["tzid"] == "UTC", "")
    # iki yone ek duzenleme turu: unicode alanlarin duzenlenmesi
    d.etkinlik_duzenle(uid("d-trk"), title=TR_METIN + " (masaüstü)", description="")
    m.ofset(600)
    m.etkinlik_duzenle(uid("m-trk"), title=TR_METIN + " (mobil)", location="Taşındı ✅")
    ctx.esitle(d, m, dz, "e3 unicode duzenleme turu")
    ctx.esit(d, m, dz, "e3 unicode duzenleme turu", pen)


def senaryo_olcek(ctx: Baglam):
    """2000 etkinlik / 500 gorev: sure olc, saniyeler icinde bitmeli."""
    ETK, GOR, SINIR = 2000, 500, 15.0
    d, m, dz = ctx.cift("olcek")
    dk = d.takvim_ekle("Kişisel")
    t0 = time.perf_counter()
    base = datetime(2026, 3, 1, 6, tzinfo=timezone.utc)
    for i in range(ETK):
        b = base + timedelta(days=i % 365, hours=i % 12)
        d.etkinlik_ekle(olay(uid(f"olcek-{i}"), dk, f"Ölçek {i} 📅 Toplantı", z(b), z(b + timedelta(hours=1)), NY if i % 3 == 0 else IST,
                             description=("Açıklama " * 20) if i % 7 == 0 else None,
                             rrule="FREQ=WEEKLY;COUNT=20" if i % 5 == 0 else None, reminders=[10, 60] if i % 10 == 0 else []))
    for i in range(GOR):
        d.gorev_ekle(uid(f"gorev-{i}"), f"Görev {i}", f"not {i}" if i % 4 == 0 else None)
    ctx.sure["olcek: masaustu veri uretimi (2000+500 tek tek kayit; harness maliyeti)"] = time.perf_counter() - t0
    for ad, fn in (("masaustu disa aktarim", lambda: d.disa(dz / "buyuk-d.takvimsync")),
                   ("mobil ice aktarim (2000+500)", lambda: m.ice(dz / "buyuk-d.takvimsync")),
                   ("mobil disa aktarim", lambda: m.disa(dz / "buyuk-m.takvimsync"))):
        t0 = time.perf_counter()
        fn()
        ctx.sure["olcek: " + ad] = time.perf_counter() - t0
    d2 = Masaustu(dz, "masaustu2")
    ctx._cihazlar.append(d2)
    t0 = time.perf_counter()
    r = d2.ice(dz / "buyuk-m.takvimsync")
    ctx.sure["olcek: masaustu ice aktarim (2000+500)"] = time.perf_counter() - t0
    ctx.kontrol("olcek: sayilar", r["event"]["added"] >= ETK and r["task"]["added"] == GOR, r)
    t0 = time.perf_counter()
    oz = d2.acilim("2026-06-01T00:00:00Z", "2026-07-01T00:00:00Z")
    ctx.sure["olcek: masaustu 1 aylik acilim"] = time.perf_counter() - t0
    t0 = time.perf_counter()
    om = m.acilim("2026-06-01T00:00:00Z", "2026-07-01T00:00:00Z")
    ctx.sure["olcek: mobil 1 aylik acilim"] = time.perf_counter() - t0
    ctx.kontrol("olcek: 1 aylik acilim esit", not olusum_farki(oz, om, "masaustu", "mobil") and len(oz) > 100, olusum_farki(oz, om, "masaustu", "mobil"))
    sa, sb = durum(d, dz, "o1"), durum(d2, dz, "o2")
    ctx.kontrol("olcek: masaustu -> mobil -> masaustu durum esit (2000/500)", sa == sb and len(sa["events"]) >= ETK, fark(sa, sb))
    # mobilde uretilen buyuk veri -> masaustu
    mk = m.takvim_ekle("Mobil")
    m.toplu_uret(ETK, GOR, mk)
    t0 = time.perf_counter()
    m.disa(dz / "buyuk-m2.takvimsync")
    ctx.sure["olcek: mobil disa aktarim (4000+1000)"] = time.perf_counter() - t0
    d3 = Masaustu(dz, "masaustu3")
    ctx._cihazlar.append(d3)
    t0 = time.perf_counter()
    r = d3.ice(dz / "buyuk-m2.takvimsync")
    ctx.sure["olcek: masaustu ice aktarim (4000+1000)"] = time.perf_counter() - t0
    ctx.kontrol("olcek: mobilde uretilen veri masaustune ulasti", r["event"]["added"] >= 2 * ETK and r["task"]["added"] >= 2 * GOR, r)
    sm, s3 = durum(m, dz, "o3"), durum(d3, dz, "o4")
    ctx.kontrol("olcek: mobil == masaustu3 durum (4000/1000)", sm == s3, fark(sm, s3))
    t0 = time.perf_counter()
    r2 = d3.ice(dz / "buyuk-m2.takvimsync")
    ctx.sure["olcek: masaustu 2. ice aktarim (degisiklik yok)"] = time.perf_counter() - t0
    ctx.kontrol("olcek: tekrar ice aktarim 0 degisiklik", degisiklik(r2) == 0, r2)
    t0 = time.perf_counter()
    r3 = m.ice(dz / "buyuk-m.takvimsync")  # kendi eski dosyasi: degisiklik yok
    ctx.sure["olcek: mobil ice aktarim (degisiklik yok)"] = time.perf_counter() - t0
    ctx.kontrol("olcek: mobil eski dosya 0 degisiklik", degisiklik(r3) == 0, r3)
    olcum = {k: v for k, v in ctx.sure.items() if "harness maliyeti" not in k}
    yavas = {k: round(v, 2) for k, v in olcum.items() if v > SINIR}
    ctx.kontrol(f"olcek: her adim <= {SINIR:.0f} sn", not yavas, yavas)


# ================================================================= senaryo f


def _gecerli_dosya(ctx: Baglam):
    """Hata dosyalari icin temel: masaustunun urettigi zengin gecerli dosya (dict)."""
    d, m, dz = ctx.cift("f-kaynak")
    kis = d.takvim_ekle("Kişisel")
    for e in cesitli(kis, kis, "f")[:6]:
        d.etkinlik_ekle(e)
    d.gorev_ekle(uid("fg1"), "Görev")
    d.gorev_ekle(uid("fg2"), "Planlı")
    d.gorev_saat(uid("fg2"), Y(IST, 2026, 11, 9, 14), Y(IST, 2026, 11, 9, 15), kis, IST)
    d.etkinlik_ekle(olay(uid("fsil"), kis, "x", Y(IST, 2026, 11, 7, 9), Y(IST, 2026, 11, 7, 10)))
    d.etkinlik_sil(uid("fsil"))
    f = dz / "kaynak.takvimsync"
    d.disa(f)
    return oku(f)


def _degis(d: dict, tur: str, fn):
    """Listenin ilk kaydini degistirir; etkinlikte bir gorev blogu OLMAYAN ("f-" onekli) kaydi."""
    d = json.loads(json.dumps(d))
    liste = d.get(tur)
    if isinstance(liste, list) and liste:
        fn(next((k for k in liste if str(k.get("uid", "")).startswith("f-")), liste[0]))
    else:
        fn(d)
    return d


def _tur_ekle(d: dict, tur: str, anahtar: str, deger):
    return _degis(d, tur, lambda k: k.__setitem__(anahtar, deger))


def _tur_sil(d: dict, tur: str, anahtar: str):
    return _degis(d, tur, lambda k: k.pop(anahtar))


def senaryo_f(ctx: Baglam):
    """Bozuk/eksik/yeni surum/farkli uzanti: iki taraf anlasilir hata verir, veri degismez."""
    g = _gecerli_dosya(ctx)
    sayac = [0]

    def taze():
        """Hedef cihazlarda onceden BASKA veri olsun: yarim birlesme olursa parmak izi degisir."""
        sayac[0] += 1
        d, m, dz = ctx.cift(f"f-{sayac[0]}")
        for c in (d, m):
            kk = c.takvim_ekle("Hedef takvim")
            c.etkinlik_ekle(olay(uid(f"hedef-{c.ad}"), kk, "Hedef", Y(IST, 2026, 11, 3, 10), Y(IST, 2026, 11, 3, 11)))
            c.gorev_ekle(uid(f"hedefg-{c.ad}"), "Hedef görev")
        return d, m, dz

    def dosyala(dz, ad, icerik) -> Path:
        p = dz / ad
        p.write_bytes(icerik if isinstance(icerik, bytes) else json.dumps(icerik, ensure_ascii=False).encode("utf-8"))
        return p

    def js(x):
        return json.dumps(x, ensure_ascii=False)

    kopya = lambda: json.loads(json.dumps(g))  # noqa: E731
    reddedilecek: dict[str, bytes | dict] = {
        "bos dosya": b"", "yalniz bosluk": b"   \n", "metin": b"merhaba", "yarim JSON": js(g).encode()[: len(js(g)) // 2],
        "JSON dizisi": b"[]", "JSON null": b"null", "JSON sayi": b"123", "format yok": b'{"version": 1}',
        "gecersiz UTF-8": b'{"format": "takvim-sync", "version": 1, "x": "\xff\xfe\x00"}',
        "UTF-16 dosya": js(g).encode("utf-16"), "ICS icerigi": b"BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n",
        "depo dosyasi (takvim-store)": js({"format": "takvim-store", "version": 1, "data": {}}).encode(),
    }
    reddedilecek.update({
        "format baska": {**kopya(), "format": "baska"}, "version metin": {**kopya(), "version": "1"},
        "version 0": {**kopya(), "version": 0}, "version -1": {**kopya(), "version": -1}, "version ondalik": {**kopya(), "version": 1.5},
        "version true": {**kopya(), "version": True}, "version yok": {k: v for k, v in kopya().items() if k != "version"},
        "takvimler liste degil": {**kopya(), "calendars": {"a": 1}},
        "takvim nesne degil": {**kopya(), "calendars": [1]},
        "olaylar liste degil": {**kopya(), "events": "x"},
        "silinenler liste degil": {**kopya(), "deleted": 5},
        "etkinlik baslik yok": _tur_sil(kopya(), "events", "title"),
        "etkinlik uid yok": _tur_sil(kopya(), "events", "uid"),
        "etkinlik calendar_uid yok": _tur_sil(kopya(), "events", "calendar_uid"),
        "etkinlik tzid yok": _tur_sil(kopya(), "events", "tzid"),
        "etkinlik updated_at yok": _tur_sil(kopya(), "events", "updated_at"),
        "etkinlik baslik sayi": _tur_ekle(kopya(), "events", "title", 5),
        "etkinlik start sayi": _tur_ekle(kopya(), "events", "start_utc", 1700000000),
        "etkinlik start +03:00": _tur_ekle(kopya(), "events", "start_utc", "2026-11-03T10:00:00+03:00"),
        "etkinlik start mikrosaniye": _tur_ekle(kopya(), "events", "start_utc", "2026-11-03T10:00:00.000Z"),
        "etkinlik start Z yok": _tur_ekle(kopya(), "events", "start_utc", "2026-11-03T10:00:00"),
        "etkinlik start ay 13": _tur_ekle(kopya(), "events", "start_utc", "2026-13-03T10:00:00Z"),
        "etkinlik start 30 subat": _tur_ekle(kopya(), "events", "start_utc", "2026-02-30T10:00:00Z"),
        "etkinlik bitis<=baslangic": _degis(kopya(), "events", lambda e: e.__setitem__("end_utc", e["start_utc"])),
        "etkinlik tzid gecersiz": _tur_ekle(kopya(), "events", "tzid", "Mars/Phobos"),
        "etkinlik tzid bos": _tur_ekle(kopya(), "events", "tzid", ""),
        "etkinlik all_day 1": _tur_ekle(kopya(), "events", "all_day", 1),
        "etkinlik all_day gece yarisi degil": _tur_ekle(kopya(), "events", "all_day", True),
        "etkinlik rrule sayi": _tur_ekle(kopya(), "events", "rrule", 5),
        "etkinlik rrule cozulemez (FREQ=BOGUS)": _tur_ekle(kopya(), "events", "rrule", "FREQ=BOGUS;;;"),
        "etkinlik rrule cozulemez (COUNT=x)": _tur_ekle(kopya(), "events", "rrule", "FREQ=DAILY;COUNT=x"),
        "etkinlik rrule cozulemez (BYDAY=XX)": _tur_ekle(kopya(), "events", "rrule", "FREQ=WEEKLY;BYDAY=XX"),
        "etkinlik reminders metin": _tur_ekle(kopya(), "events", "reminders", ["a"]),
        "etkinlik reminders negatif": _tur_ekle(kopya(), "events", "reminders", [-5]),
        "etkinlik reminders ondalik": _tur_ekle(kopya(), "events", "reminders", [1.5]),
        "etkinlik reminders liste degil": _tur_ekle(kopya(), "events", "reminders", 10),
        "etkinlik reminders cok buyuk (10**30)": _tur_ekle(kopya(), "events", "reminders", [10**30]),
        "etkinlik rdate metin": _tur_ekle(kopya(), "events", "rdate", "x"),
        "etkinlik rdate gecersiz zaman": _tur_ekle(kopya(), "events", "rdate", ["dun"]),
        "etkinlik exdate sayi": _tur_ekle(kopya(), "events", "exdate", [5]),
        "etkinlik overrides nesne degil": _tur_ekle(kopya(), "events", "overrides", [1]),
        "etkinlik override zamansiz": _tur_ekle(kopya(), "events", "overrides", [{"cancelled": True}]),
        "etkinlik override bitis<baslangic": _tur_ekle(kopya(), "events", "overrides", [
            ov("2026-11-03T10:00:00Z", bas="2026-11-03T12:00:00Z", bit="2026-11-03T11:00:00Z")]),
        "etkinlik override ayni ornek iki kez": _tur_ekle(kopya(), "events", "overrides", [
            ov("2026-11-03T10:00:00Z", iptal=True), ov("2026-11-03T10:00:00Z", baslik="x")]),
        "etkinlik description sayi": _tur_ekle(kopya(), "events", "description", 7),
        "ayni uid iki etkinlik": {**kopya(), "events": kopya()["events"] + [kopya()["events"][0]]},
        "takvim ad yok": _tur_sil(kopya(), "calendars", "name"),
        "takvim ad bos": _tur_ekle(kopya(), "calendars", "name", "   "),
        "takvim renk gecersiz": _tur_ekle(kopya(), "calendars", "color", "kirmizi"),
        "takvim renk CSS enjeksiyonu": _tur_ekle(kopya(), "calendars", "color", "red;} body{display:none"),
        "takvim visible 0": _tur_ekle(kopya(), "calendars", "visible", 0),
        "takvim updated_at yok": _tur_sil(kopya(), "calendars", "updated_at"),
        "ayni uid iki takvim": {**kopya(), "calendars": kopya()["calendars"] * 2},
        "gorev baslik bos": _tur_ekle(kopya(), "tasks", "title", "  "),
        "gorev uid yok": _tur_sil(kopya(), "tasks", "uid"),
        "gorev plan_day gecersiz": _tur_ekle(kopya(), "tasks", "plan_day", "2026-02-30"),
        "gorev plan_day ve event_uid": _tur_ekle(_tur_ekle(kopya(), "tasks", "plan_day", "2026-11-05"), "tasks", "event_uid", "x"),
        "gorev done_at gecersiz": _tur_ekle(kopya(), "tasks", "done_at", "bugun"),
        "gorev updated_at yok": _tur_sil(kopya(), "tasks", "updated_at"),
        "ayni uid iki gorev": {**kopya(), "tasks": kopya()["tasks"] * 2},
        "silinen tur bilinmiyor": {**kopya(), "deleted": [{"kind": "alarm", "uid": "x", "deleted_at": "2026-11-01T00:00:00Z"}]},
        "silinen zaman bozuk": {**kopya(), "deleted": [{"kind": "event", "uid": "x", "deleted_at": "dun"}]},
        "silinen uid yok": {**kopya(), "deleted": [{"kind": "event", "deleted_at": "2026-11-01T00:00:00Z"}]},
    })
    # Yalniz vekil karakter (JSON'da gecerli kacis, UTF-8'e yazilamaz): masaustu anlasilir hatayla reddeder.
    # Mobil bunu simdilik kabul ediyor (kendi disa aktarimi U+FFFD'ye cevirir, dosya bozulmaz): bilinen fark.
    d, _, dz = taze()
    iz = d.parmak_izi()
    p = dosyala(dz, "vekil.takvimsync", json.dumps(_tur_ekle(kopya(), "events", "title", "x" + chr(0xD800) + "y"),
                                                   ensure_ascii=True).encode("ascii"))
    try:
        d.ice(p)
        vekil_ok = False
    except Reddedildi as h:
        vekil_ok = h.anlasilir
    ctx.kontrol("f red: yalniz vekil karakter (masaustu anlasilir hata, veri degismedi)", vekil_ok and d.parmak_izi() == iz, "")
    surum = {"version 2": {**kopya(), "version": 2}, "version 999": {**kopya(), "version": 999}}
    kabul = {
        "bilinmeyen alanlar (ileri uyum)": {**kopya(), "gelecek": {"x": 1}, "events": [{**e, "yeni_alan": [1, 2]} for e in kopya()["events"]]},
        "device yok": {k: v for k, v in kopya().items() if k != "device"},
        "created_at yok": {k: v for k, v in kopya().items() if k != "created_at"},
        "takvim adi kenar bosluklu": _tur_ekle(kopya(), "calendars", "name", "  Boşluklu ad  "),
        "yinelenen/sirasiz exdate-rdate": _tur_ekle(_tur_ekle(kopya(), "events", "exdate", [
            "2026-11-09T07:00:00Z", "2026-11-02T07:00:00Z", "2026-11-09T07:00:00Z"]), "events", "rdate", [
            "2026-12-01T07:00:00Z", "2026-11-20T07:00:00Z", "2026-12-01T07:00:00Z"]),
        "etkinlik yil 0001 (NY)": _degis(kopya(), "events", lambda e: e.update(
            start_utc="0001-01-01T00:00:00Z", end_utc="0001-01-01T01:00:00Z", tzid="America/New_York",
            rrule=None, rdate=[], exdate=[], overrides=[])),
        "etkinlik yil 9999 (Tokyo)": _degis(kopya(), "events", lambda e: e.update(
            start_utc="9999-12-31T22:00:00Z", end_utc="9999-12-31T23:00:00Z", tzid="Asia/Tokyo",
            rrule=None, rdate=[], exdate=[], overrides=[])),
        "NUL karakteri baslikta": _tur_ekle(kopya(), "events", "title", "a\u0000b"),
        "bos listeler": {"format": "takvim-sync", "version": 1, "calendars": [], "events": [], "tasks": [], "deleted": []},
    }
    blokta = kopya()  # gorev blogu tekrarli yapilirsa gorev plansiza duser (iki cihazda da)
    blok_uid = next(t["event_uid"] for t in blokta["tasks"] if t["event_uid"])
    for e in blokta["events"]:
        if e["uid"] == blok_uid:
            e["rrule"] = "FREQ=DAILY;COUNT=3"
    kabul["gorev blogu tekrarli (blok olamaz -> gorev plansiz)"] = blokta
    for ad, icerik in reddedilecek.items():
        d, m, dz = taze()
        iz = {c.ad: c.parmak_izi() for c in (d, m)}
        p = dosyala(dz, f"red-{_n(ad)}.takvimsync", icerik)
        sonuc = {}
        for c in (d, m):
            try:
                r = c.ice(p)
                sonuc[c.ad] = f"KABUL {r['added']}/{r['updated']}/{r['deleted']}"
            except Reddedildi as h:
                sonuc[c.ad] = "ok" if h.anlasilir and h.mesaj.strip() else f"ANLASILMAZ {h.tur}: {h.mesaj[:80]}"
        ctx.kontrol(f"f red: {ad}", all(v == "ok" for v in sonuc.values()), sonuc)
        degisti = [c.ad for c in (d, m) if c.parmak_izi() != iz[c.ad]]
        ctx.kontrol(f"f red: {ad}: veri degismedi", not degisti, degisti)
    for ad, icerik in surum.items():
        d, m, dz = taze()
        iz = {c.ad: c.parmak_izi() for c in (d, m)}
        p = dosyala(dz, f"surum-{_n(ad)}.takvimsync", icerik)
        sonuc = {}
        for c in (d, m):
            try:
                c.ice(p)
                sonuc[c.ad] = "KABUL"
            except Reddedildi as h:
                sonuc[c.ad] = "ok" if ("güncelle" in h.mesaj) and h.anlasilir else f"MESAJ {h.tur}: {h.mesaj[:90]}"
        ctx.kontrol(f"f yeni surum: {ad} ('guncelle' mesaji, veri degismedi)",
                    all(v == "ok" for v in sonuc.values()) and all(c.parmak_izi() == iz[c.ad] for c in (d, m)), sonuc)
    for ad, icerik in kabul.items():
        d, m, dz = ctx.cift(f"f-kabul-{_n(ad)}")
        p = dosyala(dz, f"kabul-{_n(ad)}.takvimsync", icerik)
        sonuc = {}
        for c in (d, m):
            try:
                sonuc[c.ad] = c.ice(p)["added"]
            except Reddedildi as h:
                sonuc[c.ad] = f"RED {h.tur}: {h.mesaj[:90]}"
        ctx.kontrol(f"f kabul: {ad}", sonuc[d.ad] == sonuc[m.ad] and isinstance(sonuc[d.ad], int), sonuc)
        if isinstance(sonuc[d.ad], int) and sonuc[d.ad] == sonuc[m.ad]:
            ctx.esit(d, m, dz, f"f kabul: {ad} sonrasi", [PENCERE])
    # uzanti ne olursa olsun icerik belirler; BOM, CRLF, girintili/siki JSON
    kaynak = json.dumps(g, ensure_ascii=False, indent=2)
    varyant = {
        "uzanti .json": ("x.json", kaynak.encode("utf-8")), "uzanti .txt": ("x.txt", kaynak.encode("utf-8")),
        "uzanti yok": ("x", kaynak.encode("utf-8")), "uzanti .takvimsync.txt": ("x.takvimsync.txt", kaynak.encode("utf-8")),
        "UTF-8 BOM": ("bom.takvimsync", b"\xef\xbb\xbf" + kaynak.encode("utf-8")),
        "CRLF satir sonu": ("crlf.takvimsync", kaynak.replace("\n", "\r\n").encode("utf-8")),
        "siki JSON": ("siki.takvimsync", json.dumps(g, ensure_ascii=False, separators=(",", ":")).encode("utf-8")),
        "ASCII kacisli JSON": ("ascii.takvimsync", json.dumps(g, ensure_ascii=True).encode("ascii")),
        "bastaki/sondaki bosluk": ("bosluk.takvimsync", b"  \n" + kaynak.encode("utf-8") + b"\n\n  "),
    }
    ref = None
    for ad, (isim, ic) in varyant.items():
        d2, m2, dz2 = ctx.cift(f"f-uzanti-{_n(ad)}")
        p = dosyala(dz2, isim, ic)
        sonuc = {}
        for c in (d2, m2):
            try:
                sonuc[c.ad] = c.ice(p)["added"]
            except Reddedildi as h:
                sonuc[c.ad] = f"RED {h.tur}: {h.mesaj[:90]}"
        ok = isinstance(sonuc[d2.ad], int) and sonuc[d2.ad] == sonuc[m2.ad]
        if ok:
            sd, sm = durum(d2, dz2), durum(m2, dz2)
            ok = not fark(sd, sm)
            ref = ref or sd
            ok = ok and sd == ref
        ctx.kontrol(f"f biçim: {ad} ayni sonucu verir", ok, sonuc)


SENARYOLAR = {
    "a": senaryo_a, "b": senaryo_b, "c": senaryo_c, "d": senaryo_d, "e": senaryo_e, "olcek": senaryo_olcek, "f": senaryo_f,
}
