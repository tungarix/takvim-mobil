"""E2E harness: iki cihazin ortak arayuzu (masaustu = Python kodu, mobil = Dart kodu).

Iki cihaz da AYNI yontem adlariyla ve senkron dosyasi (docs/senkron.md) bicimindeki
sozluklerle surulur; aralarinda yalnizca `.takvimsync` dosyalari gecer.

- Masaustu: `takvim/senkron/` + `takvim/store/` kodu, GECICI SQLite dosyasiyla
  (gercek %LOCALAPPDATA% veritabanina dokunulmaz).
- Mobil: `lib/core` + `lib/sync` + `lib/store` kodu, `mobil_sunucu.dart` uzerinden,
  GECICI JSON deposuyla.

Saat: masaustu GERCEK saatle damgalar (SQLite tetikleyicileri 'now' kullaniyor);
mobilin saati `ofset(saniye)` ile gercek saatten kaydirilir. "Mobil sonra duzenledi"
= +600 sn, "masaustu sonra duzenledi" = -600 sn.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from dataclasses import replace
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

KOK = Path(__file__).resolve().parents[2]  # takvim-mobil
TAKVIM = Path(os.environ.get("TAKVIM_YOLU") or KOK.parent / "takvim")
sys.path.insert(0, str(TAKVIM))

from core import UTC, Event, Override, Task, parse_iso  # noqa: E402
from senkron import SenkronHatasi, durum_uret, ice_aktar, json_metni  # noqa: E402
from store import Repo  # noqa: E402

ZAMAN = "%Y-%m-%dT%H:%M:%SZ"
TURLER = ("calendar", "event", "task")


def z(d: datetime) -> str:
    return d.astimezone(UTC).strftime(ZAMAN)


def simdi(ofset: int = 0) -> datetime:
    return datetime.now(timezone.utc).replace(microsecond=0) + timedelta(seconds=ofset)


def _dt(s: str | None) -> datetime | None:
    return parse_iso(s) if s else None


class Reddedildi(Exception):
    """Cihaz dosyayi reddetti; `anlasilir` hata turu beklenen turse True."""

    def __init__(self, cihaz: str, tur: str, mesaj: str, anlasilir: bool) -> None:
        super().__init__(f"{cihaz}: {tur}: {mesaj}")
        self.cihaz, self.tur, self.mesaj, self.anlasilir = cihaz, tur, mesaj, anlasilir


# ------------------------------------------------------------------ mobil sunucu


class MobilSunucu:
    """`dart run tool/e2e/mobil_sunucu.dart` sureci; satir satir JSON."""

    def __init__(self) -> None:
        dart = shutil.which("dart")
        if not dart:
            raise SystemExit("dart bulunamadi (PATH)")
        self._log = tempfile.TemporaryFile()
        self.p = subprocess.Popen(
            [dart, "run", "tool/e2e/mobil_sunucu.dart"],
            cwd=KOK, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self._log,
        )
        self._n = 0

    def cagir(self, op: str, **kw):
        self._n += 1
        istek = {"id": self._n, "op": op, **kw}
        assert self.p.stdin and self.p.stdout
        self.p.stdin.write((json.dumps(istek) + "\n").encode("ascii"))
        self.p.stdin.flush()
        while True:
            satir = self.p.stdout.readline()
            if not satir:
                self._log.seek(0)
                raise RuntimeError(f"mobil sunucu oldu: {self._log.read().decode('utf-8', 'replace')[-2000:]}")
            try:
                y = json.loads(satir)
            except ValueError:
                continue  # "Running build hooks..." gibi gurultu
            if isinstance(y, dict) and y.get("id") == self._n:
                if not y["ok"]:
                    raise SunucuHatasi(y["tur"], y["hata"])
                return y["veri"]

    def kapat(self) -> None:
        try:
            if self.p.stdin:
                self.p.stdin.close()
            self.p.wait(timeout=10)
        except Exception:
            self.p.kill()


class SunucuHatasi(Exception):
    def __init__(self, tur: str, mesaj: str) -> None:
        super().__init__(f"{tur}: {mesaj}")
        self.tur, self.mesaj = tur, mesaj


# ------------------------------------------------------------------------- mobil


class Mobil:
    ad = "mobil"
    ANLASILIR = {"BicimHatasi", "SurumHatasi", "FormatException"}

    def __init__(self, sunucu: MobilSunucu, kimlik: str, dizin: Path, ad: str | None = None) -> None:
        self.s, self.k, self.dizin = sunucu, kimlik, dizin
        self.yol = dizin / f"{kimlik}.json"
        if ad:
            self.ad = ad
        self.s.cagir("ac", k=kimlik, yol=str(self.yol), ad=self.ad)
        self.sapma = 0

    def _c(self, op: str, **kw):
        return self.s.cagir(op, k=self.k, **kw)

    def ofset(self, saniye: int) -> None:
        self.sapma = saniye
        self._c("ofset", saniye=saniye)

    def simdi(self) -> datetime:
        return simdi(self.sapma)

    def kapat(self) -> None:
        pass

    # takvim
    def takvim_ekle(self, name: str, color: str = "#3b82f6", visible: bool = True) -> str:
        return self._c("takvim_ekle", name=name, color=color, visible=visible)

    def takvim_duzenle(self, uid: str, **alanlar) -> None:
        self._c("takvim_duzenle", uid=uid, **alanlar)

    def takvim_sil(self, uid: str) -> None:
        self._c("takvim_sil", uid=uid)

    # etkinlik
    def etkinlik_ekle(self, e: dict) -> str:
        e = {**e, "created_at": z(self.simdi()), "updated_at": z(self.simdi())}
        return self._c("etkinlik_ekle", event=e)

    def etkinlik_duzenle(self, uid: str, **alanlar) -> None:
        self._c("etkinlik_duzenle", uid=uid, alanlar=alanlar)

    def etkinlik_sil(self, uid: str) -> None:
        self._c("etkinlik_sil", uid=uid)

    def etkinlik_sil_geri_alinabilir(self, uid: str) -> None:
        self._c("etkinlik_sil_geri_alinabilir", uid=uid)

    def geri_al(self) -> None:
        self._c("geri_al")

    def override_koy(self, uid: str, ov: dict) -> None:
        self._c("override_koy", uid=uid, ov=ov)

    def override_sil(self, uid: str, original_start_utc: str) -> None:
        self._c("override_sil", uid=uid, original_start_utc=original_start_utc)

    def hatirlatici_ekle(self, uid: str, dakika: int) -> None:
        self._c("hatirlatici_ekle", uid=uid, dakika=dakika)

    def hatirlatici_sil(self, uid: str, dakika: int) -> None:
        self._c("hatirlatici_sil", uid=uid, dakika=dakika)

    # gorev
    def gorev_ekle(self, uid: str, title: str, notes: str | None = None) -> str:
        return self._c("gorev_ekle", uid=uid, title=title, notes=notes)

    def gorev_guncelle(self, uid: str, title: str | None = None, notes: str | None = None) -> None:
        self._c("gorev_guncelle", uid=uid, title=title, notes=notes)

    def gorev_tamamla(self, uid: str, done: bool = True) -> None:
        self._c("gorev_tamamla", uid=uid, done=done)

    def gorev_gun(self, uid: str, day: str) -> None:
        self._c("gorev_gun", uid=uid, day=day)

    def gorev_plan_temizle(self, uid: str) -> None:
        self._c("gorev_plan_temizle", uid=uid)

    def gorev_saat(self, uid: str, start_utc: str, end_utc: str, calendar_uid: str, tzid: str) -> None:
        self._c("gorev_saat", uid=uid, start_utc=start_utc, end_utc=end_utc, calendar_uid=calendar_uid, tzid=tzid)

    def gorev_sil(self, uid: str) -> None:
        self._c("gorev_sil", uid=uid)

    # dosya
    def disa(self, yol: Path) -> None:
        self._c("disa", yol=str(yol))

    def ice(self, yol: Path) -> dict:
        try:
            return self._c("ice", yol=str(yol))
        except SunucuHatasi as h:
            raise Reddedildi(self.ad, h.tur, h.mesaj, h.tur in self.ANLASILIR) from None

    def acilim(self, bas: str, bit: str) -> list[dict]:
        return self._c("acilim", bas=bas, bit=bit)

    def parmak_izi(self):
        """Depodaki tum veri (cihaz kimligi dahil degil): 'hicbir sey degismedi' kaniti."""
        return json.loads(self.yol.read_text(encoding="utf-8"))["data"]

    def toplu_uret(self, etkinlik: int, gorev: int, calendar_uid: str) -> None:
        self._c("toplu_uret", etkinlik=etkinlik, gorev=gorev, calendar_uid=calendar_uid)


# --------------------------------------------------------------------- masaustu


class Masaustu:
    ad = "masaustu"

    def __init__(self, dizin: Path, kimlik: str = "masaustu", ad: str | None = None) -> None:
        self.dizin = dizin
        self.kimlik = kimlik
        if ad:
            self.ad = ad
        self.repo = Repo.open(dizin / f"{kimlik}.db")
        self.sapma = 0

    def ofset(self, saniye: int) -> None:
        # Masaustu saati kaydirilamaz (SQLite tetikleyicileri 'now' kullanir).
        assert saniye == 0, "masaustu saati kaydirilamaz; mobil ofsetini kullan"

    def simdi(self) -> datetime:
        return simdi()

    def kapat(self) -> None:
        self.repo.close()

    def _id(self, tablo: str, uid: str) -> int:
        satir = self.repo.conn.execute(f"SELECT id FROM {tablo} WHERE uid = ?", (uid,)).fetchone()
        if satir is None:
            raise LookupError(f"{tablo} uid bulunamadi: {uid}")
        return satir["id"]

    # takvim
    def takvim_ekle(self, name: str, color: str = "#3b82f6", visible: bool = True) -> str:
        return self.repo.add_calendar(name, color, visible).uid

    def takvim_duzenle(self, uid: str, **alanlar) -> None:
        c = self.repo.get_calendar(self._id("calendars", uid))
        self.repo.update_calendar(replace(c, **alanlar))

    def takvim_sil(self, uid: str) -> None:
        self.repo.delete_calendar(self._id("calendars", uid))

    # etkinlik
    def _event(self, e: dict, id: int | None = None) -> Event:
        return Event(
            id=id, uid=e["uid"], calendar_id=self._id("calendars", e["calendar_uid"]), title=e["title"],
            start_utc=_dt(e["start_utc"]), end_utc=_dt(e["end_utc"]), tzid=e["tzid"],
            all_day=e.get("all_day", False), rrule=e.get("rrule") or None,
            rdate=tuple(_dt(x) for x in e.get("rdate", [])), exdate=tuple(_dt(x) for x in e.get("exdate", [])),
            description=e.get("description"), location=e.get("location"),
        )

    def _override(self, event_id: int, o: dict) -> Override:
        return Override(
            event_id=event_id, original_start_utc=_dt(o["original_start_utc"]), cancelled=o.get("cancelled", False),
            new_start_utc=_dt(o.get("new_start_utc")), new_end_utc=_dt(o.get("new_end_utc")),
            new_title=o.get("new_title"), new_location=o.get("new_location"),
        )

    def etkinlik_ekle(self, e: dict) -> str:
        ev = self.repo.add_event(self._event(e))
        for d in e.get("reminders", []):
            self.repo.add_reminder(ev.id, d)
        for o in e.get("overrides", []):
            self.repo.put_override(self._override(ev.id, o))
        return ev.uid

    def etkinlik_duzenle(self, uid: str, **alanlar) -> None:
        ev = self.repo.get_event_by_uid(uid)
        kw: dict = {}
        for k, v in alanlar.items():
            if k in ("start_utc", "end_utc"):
                kw[k] = _dt(v)
            elif k in ("rdate", "exdate"):
                kw[k] = tuple(_dt(x) for x in v)
            elif k == "calendar_uid":
                kw["calendar_id"] = self._id("calendars", v)
            else:
                kw[k] = v
        self.repo.update_event(replace(ev, **kw))

    def etkinlik_sil(self, uid: str) -> None:
        self.repo.delete_event(self._id("events", uid))

    def etkinlik_sil_geri_alinabilir(self, uid: str) -> None:
        self.repo.snapshot_and_delete(self._id("events", uid))

    def geri_al(self) -> None:
        assert self.repo.restore_last_deleted() is not None

    def override_koy(self, uid: str, ov: dict) -> None:
        self.repo.put_override(self._override(self._id("events", uid), ov))

    def override_sil(self, uid: str, original_start_utc: str) -> None:
        self.repo.delete_override(self._id("events", uid), _dt(original_start_utc))

    def hatirlatici_ekle(self, uid: str, dakika: int) -> None:
        self.repo.add_reminder(self._id("events", uid), dakika)

    def hatirlatici_sil(self, uid: str, dakika: int) -> None:
        eid = self._id("events", uid)
        for r in self.repo.list_reminders(eid):
            if r.minutes_before == dakika:
                self.repo.delete_reminder(r.id)

    # gorev
    def gorev_ekle(self, uid: str, title: str, notes: str | None = None) -> str:
        return self.repo.add_task(Task(id=None, uid=uid, title=title, notes=notes)).uid

    def gorev_guncelle(self, uid: str, title: str | None = None, notes: str | None = None) -> None:
        t = self.repo.get_task_by_uid(uid)
        self.repo.update_task(replace(t, title=title if title is not None else t.title,
                                      notes=notes if notes is not None else t.notes))

    def gorev_tamamla(self, uid: str, done: bool = True) -> None:
        self.repo.set_task_done(self._id("tasks", uid), done)

    def gorev_gun(self, uid: str, day: str) -> None:
        self.repo.plan_task_day(self._id("tasks", uid), date.fromisoformat(day))

    def gorev_plan_temizle(self, uid: str) -> None:
        self.repo.clear_task_plan(self._id("tasks", uid))

    def gorev_saat(self, uid: str, start_utc: str, end_utc: str, calendar_uid: str, tzid: str) -> None:
        self.repo.plan_task_slot(self._id("tasks", uid), _dt(start_utc), _dt(end_utc),
                                 self._id("calendars", calendar_uid), tzid)

    def gorev_sil(self, uid: str) -> None:
        self.repo.delete_task(self._id("tasks", uid))

    # dosya
    def disa(self, yol: Path) -> None:
        d = durum_uret(self.repo, cihaz_id=self.kimlik, cihaz_adi=self.ad, uygulama="e2e")
        Path(yol).write_bytes(json_metni(d).encode("utf-8"))

    def ice(self, yol: Path) -> dict:
        try:
            r = ice_aktar(self.repo, Path(yol).read_bytes()).as_dict()
        except SenkronHatasi as h:
            raise Reddedildi(self.ad, h.kod, str(h), True) from None
        except Exception as h:  # anlasilmaz: ham istisna kullaniciya sizar
            raise Reddedildi(self.ad, type(h).__name__, str(h), False) from None
        out = {k: r["total"][k] for k in ("added", "updated", "deleted", "skipped")}
        for tur in TURLER:
            out[tur] = {k: r[k][tur] for k in ("added", "updated", "deleted", "skipped")}
        return out

    def acilim(self, bas: str, bit: str) -> list[dict]:
        uidler = {r["id"]: r["uid"] for r in self.repo.conn.execute("SELECT id, uid FROM calendars")}
        return [
            {
                "event_uid": o.uid, "calendar_uid": uidler[o.calendar_id], "title": o.title,
                "start_utc": z(o.start_utc), "end_utc": z(o.end_utc), "all_day": o.all_day,
                "location": o.location, "is_override": o.is_override,
                "original_start_utc": z(o.original_start_utc or o.start_utc),
            }
            for o in self.repo.occurrences(_dt(bas), _dt(bit), include_hidden=True)
        ]

    def parmak_izi(self):
        return [
            [tuple(r) for r in self.repo.conn.execute(f"SELECT * FROM {t} ORDER BY 1, 2")]
            for t in ("calendars", "events", "event_overrides", "reminders", "tasks", "silinenler")
        ]


# ------------------------------------------------------------ karsilastirma


def oku(yol: Path) -> dict:
    return json.loads(Path(yol).read_text(encoding="utf-8"))


def _anahtar(tur: str):
    return (lambda r: (r["kind"], r["uid"])) if tur == "deleted" else (lambda r: r["uid"])


def durum(c, dizin: Path, ad: str = "durum") -> dict:
    """Cihazin dosya olarak disa aktarilan tam durumu (olusturma/cihaz bilgisi haric, uid'e gore sirali)."""
    yol = dizin / f"{c.ad}-{ad}.takvimsync"
    c.disa(yol)
    d = oku(yol)
    return {t: sorted(d[t], key=_anahtar(t)) for t in ("calendars", "events", "tasks", "deleted")}


def canli(d: dict) -> dict:
    return {t: d[t] for t in ("calendars", "events", "tasks")}


def _kisa(v) -> str:
    s = repr(v)
    return s if len(s) < 90 else s[:87] + "..."


def fark(a: dict, b: dict, ad_a: str = "A", ad_b: str = "B") -> list[str]:
    cikti = []
    for tur in a:
        k = _anahtar(tur)
        A, B = {k(r): r for r in a[tur]}, {k(r): r for r in b[tur]}
        for u in sorted(A.keys() - B.keys(), key=str):
            cikti.append(f"{tur} {u}: yalniz {ad_a}'da")
        for u in sorted(B.keys() - A.keys(), key=str):
            cikti.append(f"{tur} {u}: yalniz {ad_b}'de")
        for u in sorted(A.keys() & B.keys(), key=str):
            for alan in sorted(set(A[u]) | set(B[u])):
                if A[u].get(alan) != B[u].get(alan):
                    cikti.append(f"{tur} {u}.{alan}: {ad_a}={_kisa(A[u].get(alan))} {ad_b}={_kisa(B[u].get(alan))}")
    return cikti


def olusum_farki(a: list[dict], b: list[dict], ad_a: str, ad_b: str) -> list[str]:
    anahtar = lambda o: (o["start_utc"], o["end_utc"], o["event_uid"], o["original_start_utc"])  # noqa: E731
    sa, sb = sorted(a, key=anahtar), sorted(b, key=anahtar)
    if sa == sb:
        return []
    ka, kb = {anahtar(o): o for o in sa}, {anahtar(o): o for o in sb}
    out = [f"olusum sayisi: {ad_a}={len(sa)} {ad_b}={len(sb)}"]
    for k in sorted(ka.keys() - kb.keys())[:5]:
        out.append(f"yalniz {ad_a}: {ka[k]['event_uid']} {k[0]}..{k[1]}")
    for k in sorted(kb.keys() - ka.keys())[:5]:
        out.append(f"yalniz {ad_b}: {kb[k]['event_uid']} {k[0]}..{k[1]}")
    for k in sorted(ka.keys() & kb.keys()):
        if ka[k] != kb[k]:
            out.append(f"alan farki {k}: {ka[k]} != {kb[k]}")
            break
    return out


def degisiklik(r: dict) -> int:
    return r["added"] + r["updated"] + r["deleted"]


def gonder(kaynak, hedef, dizin: Path, ad: str | None = None) -> dict:
    """kaynak cihazin tam durumunu dosyaya yazar, hedef cihaza iceri aktarir."""
    yol = dizin / (ad or f"{kaynak.ad}-{hedef.ad}.takvimsync")
    kaynak.disa(yol)
    return hedef.ice(yol)
