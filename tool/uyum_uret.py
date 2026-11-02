"""Masaüstü açıcısından (core/recurrence.py) uyum fixture'ı üretir.

Masaüstü deposu OKUNUR, değiştirilmez. Kullanım (masaüstünün .venv'iyle):
    <takvim>/.venv/Scripts/python.exe -I tool/uyum_uret.py <takvim yolu> test/fixtures/uyum-yerel.json
Dart tarafı test/uyum_test.dart aynı senaryoları kendi açıcısıyla çalıştırıp birebir karşılaştırır.
"""
import json
import sys
from datetime import datetime, timezone

sys.path.insert(0, sys.argv[1])
from core.models import Event, Override  # noqa: E402
from core.recurrence import expand  # noqa: E402

UTC = timezone.utc
F = "%Y-%m-%dT%H:%M:%SZ"


def t(s):
    return datetime.strptime(s, F).replace(tzinfo=UTC)


def yaz(d):
    return d.astimezone(UTC).strftime(F)


def senaryo(ad, *, tzid, start, end, rrule=None, rdate=(), exdate=(), all_day=False, overrides=(), pencere):
    ev = Event(id=1, uid="u", calendar_id=1, title="Baslik", start_utc=t(start), end_utc=t(end), tzid=tzid,
               all_day=all_day, rrule=rrule, rdate=tuple(t(x) for x in rdate), exdate=tuple(t(x) for x in exdate),
               location="Yer")
    ovs = [Override(event_id=1, original_start_utc=t(o["orig"]), cancelled=o.get("iptal", False),
                    new_start_utc=t(o["ns"]) if o.get("ns") else None, new_end_utc=t(o["ne"]) if o.get("ne") else None,
                    new_title=o.get("baslik"), new_location=o.get("yer")) for o in overrides]
    occs = expand(ev, ovs, t(pencere[0]), t(pencere[1]))
    return {
        "ad": ad,
        "pencere": list(pencere),
        "event": {
            "uid": "u", "calendar_uid": "c", "title": "Baslik", "description": None, "location": "Yer",
            "start_utc": start, "end_utc": end, "tzid": tzid, "all_day": all_day, "rrule": rrule,
            "rdate": list(rdate), "exdate": list(exdate), "reminders": [],
            "overrides": [{"original_start_utc": o["orig"], "cancelled": o.get("iptal", False),
                           "new_start_utc": o.get("ns"), "new_end_utc": o.get("ne"),
                           "new_title": o.get("baslik"), "new_location": o.get("yer")} for o in overrides],
            "created_at": start, "updated_at": start,
        },
        "olusumlar": [{"start_utc": yaz(o.start_utc), "end_utc": yaz(o.end_utc), "title": o.title,
                       "location": o.location, "is_override": o.is_override,
                       "original_start_utc": yaz(o.original_start_utc)} for o in occs],
    }


IST, NY, SYD, LON = "Europe/Istanbul", "America/New_York", "Australia/Sydney", "Europe/London"
YIL = ("2026-01-01T00:00:00Z", "2027-01-01T00:00:00Z")
S = []
a = S.append
a(senaryo("haftalik pazartesi istanbul", tzid=IST, start="2026-11-02T07:00:00Z", end="2026-11-02T08:00:00Z",
          rrule="FREQ=WEEKLY;BYDAY=MO", pencere=("2026-11-01T00:00:00Z", "2026-12-15T00:00:00Z")))
a(senaryo("haftalik uc gun aralik 2 sayili", tzid=IST, start="2026-11-02T07:00:00Z", end="2026-11-02T08:30:00Z",
          rrule="FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR;COUNT=7", pencere=YIL))
a(senaryo("aylik 31i", tzid=IST, start="2026-01-31T09:00:00Z", end="2026-01-31T10:00:00Z",
          rrule="FREQ=MONTHLY;BYMONTHDAY=31", pencere=YIL))
a(senaryo("aylik son cuma", tzid=IST, start="2026-01-30T09:00:00Z", end="2026-01-30T10:00:00Z",
          rrule="FREQ=MONTHLY;BYDAY=-1FR", pencere=YIL))
a(senaryo("aylik son is gunu setpos", tzid=LON, start="2026-01-30T09:00:00Z", end="2026-01-30T10:00:00Z",
          rrule="FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1", pencere=YIL))
a(senaryo("aylik ikinci sali", tzid=NY, start="2026-01-13T15:00:00Z", end="2026-01-13T16:00:00Z",
          rrule="FREQ=MONTHLY;BYDAY=2TU", pencere=YIL))
a(senaryo("yillik 29 subat", tzid=IST, start="2024-02-29T07:00:00Z", end="2024-02-29T08:00:00Z",
          rrule="FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29", pencere=("2024-01-01T00:00:00Z", "2033-01-01T00:00:00Z")))
a(senaryo("yillik kasim ilk pazar", tzid=NY, start="2026-11-01T15:00:00Z", end="2026-11-01T16:00:00Z",
          rrule="FREQ=YEARLY;BYMONTH=11;BYDAY=1SU", pencere=("2026-01-01T00:00:00Z", "2031-01-01T00:00:00Z")))
a(senaryo("gunluk NY ilkbahar DST 09:00", tzid=NY, start="2026-03-05T14:00:00Z", end="2026-03-05T15:00:00Z",
          rrule="FREQ=DAILY", pencere=("2026-03-01T00:00:00Z", "2026-03-15T00:00:00Z")))
a(senaryo("gunluk NY sonbahar DST 09:00", tzid=NY, start="2026-10-29T13:00:00Z", end="2026-10-29T14:00:00Z",
          rrule="FREQ=DAILY", pencere=("2026-10-25T00:00:00Z", "2026-11-08T00:00:00Z")))
a(senaryo("gunluk NY belirsiz saat 01:30", tzid=NY, start="2026-10-30T05:30:00Z", end="2026-10-30T06:30:00Z",
          rrule="FREQ=DAILY", pencere=("2026-10-28T00:00:00Z", "2026-11-05T00:00:00Z")))
a(senaryo("gunluk NY olmayan saat 02:30", tzid=NY, start="2026-03-06T07:30:00Z", end="2026-03-06T08:30:00Z",
          rrule="FREQ=DAILY", pencere=("2026-03-04T00:00:00Z", "2026-03-12T00:00:00Z")))
a(senaryo("saatlik 6 aralik DST", tzid=NY, start="2026-03-07T10:00:00Z", end="2026-03-07T10:30:00Z",
          rrule="FREQ=HOURLY;INTERVAL=6;COUNT=20", pencere=("2026-03-07T00:00:00Z", "2026-03-12T00:00:00Z")))
a(senaryo("gunluk BYHOUR", tzid=LON, start="2026-03-25T09:00:00Z", end="2026-03-25T09:30:00Z",
          rrule="FREQ=DAILY;BYHOUR=9,17;COUNT=12", pencere=("2026-03-20T00:00:00Z", "2026-04-10T00:00:00Z")))
a(senaryo("tum gun gunluk sayili", tzid=IST, start="2026-11-02T21:00:00Z", end="2026-11-03T21:00:00Z", all_day=True,
          rrule="FREQ=DAILY;COUNT=5", pencere=("2026-11-01T00:00:00Z", "2026-11-30T00:00:00Z")))
a(senaryo("tum gun haftalik sydney DST", tzid=SYD, start="2026-09-26T14:00:00Z", end="2026-09-27T14:00:00Z", all_day=True,
          rrule="FREQ=WEEKLY;COUNT=8", pencere=("2026-09-01T00:00:00Z", "2026-12-31T00:00:00Z")))
a(senaryo("until Z", tzid=IST, start="2026-11-02T07:00:00Z", end="2026-11-02T08:00:00Z",
          rrule="FREQ=WEEKLY;BYDAY=MO;UNTIL=20261116T070000Z", pencere=YIL))
a(senaryo("until sadece tarih", tzid=IST, start="2026-11-02T07:00:00Z", end="2026-11-02T08:00:00Z",
          rrule="FREQ=WEEKLY;BYDAY=MO;UNTIL=20261116", pencere=YIL))
a(senaryo("until yerel naive", tzid=NY, start="2026-11-02T14:00:00Z", end="2026-11-02T15:00:00Z",
          rrule="FREQ=DAILY;UNTIL=20261105T090000", pencere=YIL))
a(senaryo("until Z NY", tzid=NY, start="2026-11-02T14:00:00Z", end="2026-11-02T15:00:00Z",
          rrule="FREQ=DAILY;UNTIL=20261104T140000Z", pencere=YIL))
a(senaryo("rdate exdate", tzid=IST, start="2026-11-02T07:00:00Z", end="2026-11-02T08:00:00Z",
          rrule="FREQ=WEEKLY;BYDAY=MO", rdate=["2026-11-05T09:00:00Z", "2026-11-12T09:00:00Z"],
          exdate=["2026-11-09T07:00:00Z", "2026-11-23T07:00:00Z"], pencere=("2026-11-01T00:00:00Z", "2026-12-01T00:00:00Z")))
a(senaryo("rrule yok rdate exdate", tzid=IST, start="2026-11-02T07:00:00Z", end="2026-11-02T08:00:00Z",
          rdate=["2026-11-05T09:00:00Z", "2026-11-12T09:00:00Z"], exdate=["2026-11-05T09:00:00Z"],
          pencere=("2026-11-01T00:00:00Z", "2026-12-01T00:00:00Z")))
a(senaryo("tekrarsiz", tzid=IST, start="2026-11-02T07:00:00Z", end="2026-11-02T08:00:00Z",
          pencere=("2026-11-01T00:00:00Z", "2026-12-01T00:00:00Z")))
a(senaryo("tekrarsiz pencere disi", tzid=IST, start="2026-11-02T07:00:00Z", end="2026-11-02T08:00:00Z",
          pencere=("2026-11-02T08:00:00Z", "2026-11-03T00:00:00Z")))
a(senaryo("override iptal tasima baslik", tzid=IST, start="2026-11-02T07:00:00Z", end="2026-11-02T08:00:00Z",
          rrule="FREQ=WEEKLY;BYDAY=MO", pencere=("2026-11-01T00:00:00Z", "2026-12-01T00:00:00Z"),
          overrides=[{"orig": "2026-11-09T07:00:00Z", "iptal": True},
                     {"orig": "2026-11-16T07:00:00Z", "ns": "2026-11-17T12:00:00Z"},
                     {"orig": "2026-11-23T07:00:00Z", "ns": "2026-11-23T10:00:00Z", "ne": "2026-11-23T13:00:00Z",
                      "baslik": "Yeni", "yer": "Salon"}]))
a(senaryo("override pencere disindan iceri", tzid=IST, start="2026-11-02T07:00:00Z", end="2026-11-02T08:00:00Z",
          rrule="FREQ=WEEKLY;BYDAY=MO", pencere=("2026-12-01T00:00:00Z", "2026-12-08T00:00:00Z"),
          overrides=[{"orig": "2026-11-23T07:00:00Z", "ns": "2026-12-03T10:00:00Z"}]))
a(senaryo("override hayalet", tzid=IST, start="2026-11-02T07:00:00Z", end="2026-11-02T08:00:00Z",
          rrule="FREQ=WEEKLY;BYDAY=MO", pencere=("2026-11-01T00:00:00Z", "2026-12-01T00:00:00Z"),
          overrides=[{"orig": "2026-11-10T07:00:00Z", "ns": "2026-11-11T07:00:00Z"}]))
a(senaryo("override sayili bitmis seriden", tzid=IST, start="2026-01-05T07:00:00Z", end="2026-01-05T08:00:00Z",
          rrule="FREQ=WEEKLY;BYDAY=MO;COUNT=3", pencere=("2026-03-01T00:00:00Z", "2026-03-10T00:00:00Z"),
          overrides=[{"orig": "2026-01-19T07:00:00Z", "ns": "2026-03-04T07:00:00Z"}]))
a(senaryo("dtstart desene uymuyor", tzid=IST, start="2026-11-03T07:00:00Z", end="2026-11-03T08:00:00Z",
          rrule="FREQ=WEEKLY;BYDAY=MO", pencere=("2026-11-01T00:00:00Z", "2026-12-01T00:00:00Z")))
a(senaryo("dtstart desene uymuyor sayili", tzid=IST, start="2026-11-03T07:00:00Z", end="2026-11-03T08:00:00Z",
          rrule="FREQ=WEEKLY;BYDAY=MO;COUNT=2", pencere=("2026-11-01T00:00:00Z", "2026-12-31T00:00:00Z")))
a(senaryo("cok gunluk pencereye sarkan", tzid=IST, start="2026-11-01T07:00:00Z", end="2026-11-03T08:00:00Z",
          rrule="FREQ=WEEKLY;COUNT=4", pencere=("2026-11-09T00:00:00Z", "2026-11-10T00:00:00Z")))
a(senaryo("bitis tam pencere basinda", tzid=IST, start="2026-11-02T07:00:00Z", end="2026-11-02T08:00:00Z",
          rrule="FREQ=DAILY;COUNT=3", pencere=("2026-11-03T08:00:00Z", "2026-11-04T07:00:00Z")))
a(senaryo("aylik aralik 2 sayili", tzid=SYD, start="2026-01-15T00:00:00Z", end="2026-01-15T01:00:00Z",
          rrule="FREQ=MONTHLY;INTERVAL=2;COUNT=5", pencere=YIL))
a(senaryo("yillik sonsuz uzak pencere", tzid=IST, start="2020-05-05T07:00:00Z", end="2020-05-05T08:00:00Z",
          rrule="FREQ=YEARLY", pencere=("2026-01-01T00:00:00Z", "2028-01-01T00:00:00Z")))
json.dump(S, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(len(S), "senaryo,", sum(len(x["olusumlar"]) for x in S), "olusum")
