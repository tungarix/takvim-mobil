// Etkinlik ekle/düzenle formu (tam ekran).
//
// Kapsamlar (tekrarlı etkinlik): tümü (seriyi değiştirir), yalnız bu örnek (override:
// başlık/saat/konum), bu ve sonrakiler (seri bölünür, yeni parçaya form uygulanır).
// Tümünde/sonrakilerde seri çapası, ekranda GÖRÜNEN örnekte yapılan değişiklik
// kadar (delta) kaydırılır; çapanın günü hep örneğin günü olmayabilir.
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../app/kontrol.dart';
import '../core/models.dart';
import '../core/tekrar.dart';
import '../core/recurrence.dart';
import '../core/veri.dart';
import '../core/yerel_zaman.dart';
import 'bicim.dart';
import 'dogum_gunu.dart';
import 'etkinlik_islemleri.dart';
import 'metin.dart';

const _hatirlaticiSecenekleri = [0, 5, 10, 15, 30, 60, 120, 1440, 2880, 10080];
// Tüm gün etkinliği gece yarısı başlar: 900 = önceki gün 09:00 (sabahtan sonrası "o gün" ifade edilemez, süre >= 0).
const _dogumHatirlaticiSecenekleri = [900, 0, 1440, 2880, 10080];

class EtkinlikFormu extends StatefulWidget {
  const EtkinlikFormu({super.key, required this.kontrol, this.ornek, this.kapsam = Kapsam.tumu, this.baslangic});

  final TakvimKontrol kontrol;

  /// Düzenlenen örnek; null ise yeni etkinlik.
  final Occurrence? ornek;
  final Kapsam kapsam;

  /// Yeni etkinlik için duvar başlangıcı.
  final DateTime? baslangic;

  @override
  State<EtkinlikFormu> createState() => _EtkinlikFormuDurumu();
}

class _EtkinlikFormuDurumu extends State<EtkinlikFormu> {
  final _anahtar = GlobalKey<FormState>();
  final _baslik = TextEditingController();
  final _konum = TextEditingController();
  final _aciklama = TextEditingController();
  final _sayi = TextEditingController(text: '10');

  late String _takvimUid;
  late bool _tumGun;
  late DateTime _bas; // duvar tarih+saat; tüm günde yalnız tarih
  late DateTime _bit; // saatlide duvar bitişi; tüm günde SON gün (dahil)
  TekrarAyari _tekrar = const TekrarAyari();
  Set<int> _ekGunler = {}; // başlangıç gününe ek haftalık günler
  bool _ozelTekrar = false;
  late Set<int> _hat;
  // Doğum günü modu (yalnız yeni eklemede): ayrı hatırlatıcı kümesi, tür değişince diğerini bozmaz.
  bool _dogumGunu = false;
  final Set<int> _dgHat = {900};
  late DateTime _dgTarih; // yıl yalnız _dgYilVar iken anlamlı
  bool _dgYilVar = false;
  late String _ilkTekrar;
  late int _ilkBasHaftaGunu;
  late Set<int> _ilkEk;
  String? _bitisHata;
  bool _kaydediyor = false;

  TakvimKontrol get k => widget.kontrol;
  Event? get _e => widget.ornek == null ? null : k.veri.events[widget.ornek!.eventUid];
  bool get _yeni => widget.ornek == null;
  bool get _buOrnek => widget.kapsam == Kapsam.buOrnek;

  /// Etkinliğin kendi saat dilimi: tüm gün ve tekrar duvar saati bununla çözülür.
  YerelZaman get _etkinlikTz => YerelZaman(_e?.tzid ?? k.zaman.tzid);

  String _tekrarAnahtar() => '${_tekrar.tur}|${_tekrar.bitis}|${_tekrar.bitisGunu}|${int.tryParse(_sayi.text) ?? _tekrar.sayi}|$_ozelTekrar';

  /// Başlangıç günü kaydıkça haftalık günler de aynı kadar kayar; "değişmedi" sayılması için
  /// ilk ek günler aynı kadar kaydırılıp karşılaştırılır.
  Set<int> _kaydirilmisIlkEk() {
    final kayma = (_bas.weekday - _ilkBasHaftaGunu) % 7;
    return {for (final g in _ilkEk) ((g - 1 + kayma) % 7) + 1}..remove(_bas.weekday);
  }

  bool get _tekrarDegisti =>
      _tekrarAnahtar() != _ilkTekrar || (_tekrar.tur == TekrarTuru.haftalik && !setEquals(_kaydirilmisIlkEk(), _ekGunler));

  @override
  void initState() {
    super.initState();
    final e = _e;
    final o = widget.ornek;
    if (e == null || o == null) {
      _bas = widget.baslangic ?? k.bugun;
      _bit = _bas.add(const Duration(hours: 1));
      _takvimUid = k.varsayilanTakvim!.uid;
      _tumGun = false;
      _hat = {};
      _dgTarih = gunDuvar(_bas);
    } else {
      _tumGun = e.allDay;
      _dgTarih = gunDuvar(o.start);
      if (e.allDay) {
        final tz = YerelZaman(e.tzid);
        _bas = gunDuvar(tz.duvar(o.start));
        final son = gunEkle(gunDuvar(tz.duvar(o.end)), -1);
        _bit = son.isBefore(_bas) ? _bas : son;
      } else {
        _bas = k.zaman.duvar(o.start);
        _bit = k.zaman.duvar(o.end);
      }
      _baslik.text = o.title;
      _konum.text = o.location ?? '';
      _aciklama.text = e.description ?? '';
      _takvimUid = e.calendarUid;
      _hat = {...e.reminders};
      final tz = YerelZaman(e.tzid);
      final a = tekrarOku(e.rrule, baslangic: tz.duvar(o.originalStart), loc: tz.loc);
      if (a == null || (e.rrule == null && e.rdate.isNotEmpty)) {
        _ozelTekrar = true;
      } else {
        _tekrar = a;
        _sayi.text = '${a.sayi}';
        _ekGunler = a.tur == TekrarTuru.haftalik ? ({...a.gunler}..remove(_bas.weekday)) : {};
      }
    }
    _ilkTekrar = _tekrarAnahtar();
    _ilkBasHaftaGunu = _bas.weekday;
    _ilkEk = {..._ekGunler};
  }

  @override
  void dispose() {
    _baslik.dispose();
    _konum.dispose();
    _aciklama.dispose();
    _sayi.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ seçiciler

  Future<DateTime?> _tarihSec(DateTime ilk) async {
    final r = await showDatePicker(context: context, initialDate: DateTime(ilk.year, ilk.month, ilk.day), firstDate: DateTime(2000), lastDate: DateTime(2100));
    return r == null ? null : DateTime.utc(r.year, r.month, r.day);
  }

  Future<TimeOfDay?> _saatSec(DateTime ilk) => showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: ilk.hour, minute: ilk.minute),
        builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: w!),
      );

  void _basDegistir(DateTime yeni) {
    setState(() {
      final fark = yeni.difference(_bas);
      final kayma = (yeni.weekday - _bas.weekday) % 7;
      _bas = yeni;
      _bit = _bit.add(fark); // süre korunur
      if (_tekrar.tur == TekrarTuru.haftalik) {
        _ekGunler = {for (final g in _ekGunler) ((g - 1 + kayma) % 7) + 1}..remove(yeni.weekday);
      }
    });
  }

  // ------------------------------------------------------------ kaydet

  String? _bos(String s) => s.trim().isEmpty ? null : s.trim();

  Future<void> _dogumGunuKaydet() async {
    if (!_anahtar.currentState!.validate()) return;
    final etz = _etkinlikTz;
    final kayit = dogumGunuKur(ay: _dgTarih.month, gun: _dgTarih.day, yil: _dgYilVar ? _dgTarih.year : null, bugun: k.bugun);
    final basUtc = etz.utc(kayit.baslangic);
    final bitUtc = etz.utc(gunEkle(kayit.baslangic, 1));
    final baslik = M.dogumGunuBasligi(_baslik.text.trim());
    setState(() => _kaydediyor = true);
    final ok = await k.yap((v) => v.addEvent(Event(
          uid: '${yeniUuid()}@takvim.local', calendarUid: _takvimUid, title: baslik, start: basUtc, end: bitUtc, tzid: etz.tzid,
          allDay: true, rrule: kayit.rrule, reminders: {..._dgHat}, createdAt: v.simdi, updatedAt: v.simdi,
        )));
    if (!mounted) return;
    setState(() => _kaydediyor = false);
    if (ok) {
      k.odakAyarla(kayit.baslangic);
      Navigator.of(context).pop();
    }
  }

  Future<void> _kaydet() async {
    if (_dogumGunu) return _dogumGunuKaydet();
    setState(() => _bitisHata = null);
    if (!_anahtar.currentState!.validate()) return;
    final etz = _etkinlikTz;
    final basUtc = _tumGun ? etz.utc(gunDuvar(_bas)) : k.zaman.utc(_bas);
    final bitUtc = _tumGun ? etz.utc(gunEkle(gunDuvar(_bit), 1)) : k.zaman.utc(_bit);
    if (!bitUtc.isAfter(basUtc)) {
      setState(() => _bitisHata = M.bitisHataliEtkinlik);
      return;
    }
    // UNTIL, DTSTART'tan önce olursa etkinlik hiçbir günde görünmez (sessiz kayıp).
    if (!_buOrnek && _tekrar.tur != TekrarTuru.yok && _tekrar.bitis == TekrarBitisi.tarih &&
        _tekrar.bitisGunu != null && _tekrar.bitisGunu!.isBefore(gunDuvar(_bas))) {
      setState(() => _bitisHata = M.tekrarBitisOnce);
      return;
    }
    setState(() => _kaydediyor = true);
    final baslik = _baslik.text.trim();
    final ok = await k.yap((v) => _uygula(v, baslik, basUtc, bitUtc, etz));
    if (!mounted) return;
    setState(() => _kaydediyor = false);
    if (ok) {
      if (_yeni) k.odakAyarla(gunDuvar(_bas));
      Navigator.of(context).pop();
    }
  }

  /// Formdan etkinlik üretir ve `v` üzerine yazar (kopya üzerinde çalışır; hata atarsa hiçbir şey yazılmaz).
  void _uygula(Veri v, String baslik, DateTime basUtc, DateTime bitUtc, YerelZaman etz) {
    final e = _e;
    final o = widget.ornek;
    if (e == null || o == null) {
      final rrule = _tekrarMetni(etz.duvar(basUtc), etz);
      v.addEvent(Event(
        uid: '${yeniUuid()}@takvim.local', calendarUid: _takvimUid, title: baslik, description: _bos(_aciklama.text),
        location: _bos(_konum.text), start: basUtc, end: bitUtc, tzid: etz.tzid, allDay: _tumGun, rrule: rrule,
        reminders: _hat, createdAt: v.simdi, updatedAt: v.simdi,
      ));
      return;
    }
    if (widget.kapsam == Kapsam.buOrnek) {
      final konum = _bos(_konum.text) ?? ''; // null = seriden miras; boşaltma '' olarak saklanır
      v.putOverride(e.uid, EventOverride(
        originalStart: o.originalStart, newStart: basUtc, newEnd: bitUtc,
        newTitle: baslik != e.title ? baslik : null, newLocation: konum != (e.location ?? '') ? konum : null,
      ));
      return;
    }
    var hedef = e;
    if (widget.kapsam == Kapsam.buVeSonrakiler) hedef = v.seriyiBol(e.uid, o.originalStart);

    final delta = basUtc.difference(o.start);
    final yeniBas = hedef.start.add(delta);
    final etkinlikTz = YerelZaman(hedef.tzid);
    final tekrarDegisti = _tekrarDegisti;
    final haftaKaydi = _tekrar.tur == TekrarTuru.haftalik && _bas.weekday != _ilkBasHaftaGunu;
    String? rrule = hedef.rrule;
    if (!_ozelTekrar && (tekrarDegisti || haftaKaydi || (_tekrar.tur == TekrarTuru.yok) != (hedef.rrule == null))) {
      rrule = _tekrarMetni(etkinlikTz.duvar(yeniBas), etkinlikTz);
    }
    // Kural değiştiyse eski istisnalar yeni desene oturmaz (hayalet override sessizce kaybolurdu): temizlenir.
    // Yalnız kaydırma varsa anahtarlar da aynı kadar kayar.
    final temizle = tekrarDegisti && !_ozelTekrar;
    DateTime kaydir(DateTime d) => d.add(delta);
    v.updateEvent(Event(
      uid: hedef.uid, calendarUid: _takvimUid, title: baslik, description: _bos(_aciklama.text), location: _bos(_konum.text),
      start: yeniBas, end: yeniBas.add(bitUtc.difference(basUtc)), tzid: hedef.tzid, allDay: _tumGun, rrule: rrule,
      rdate: temizle ? const [] : hedef.rdate.map(kaydir), exdate: temizle ? const [] : hedef.exdate.map(kaydir),
      reminders: _hat,
      overrides: temizle
          ? const []
          : hedef.overrides.map((x) => EventOverride(
                originalStart: kaydir(x.originalStart), cancelled: x.cancelled, newStart: x.newStart, newEnd: x.newEnd,
                newTitle: x.newTitle, newLocation: x.newLocation)),
      createdAt: hedef.createdAt, updatedAt: hedef.updatedAt,
    ));
  }

  String? _tekrarMetni(DateTime baslangicDuvar, YerelZaman etz) {
    final efektif = _tekrar.kopya(
      gunler: _tekrar.tur == TekrarTuru.haftalik ? {..._ekGunler, baslangicDuvar.weekday} : const {},
      sayi: int.tryParse(_sayi.text) ?? _tekrar.sayi,
    );
    return tekrarYaz(efektif, baslangic: baslangicDuvar, loc: etz.loc);
  }

  // ------------------------------------------------------------ arayüz

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final takvimler = k.takvimlerSirali;
    final takvim = takvimler.where((c) => c.uid == _takvimUid).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: M.iptal, icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
        actions: [
          if (!_yeni)
            IconButton(
              tooltip: M.sil,
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final nav = Navigator.of(context);
                if (await etkinlikSil(context, k, widget.ornek!) && nav.mounted) nav.pop();
              },
            ),
          IconButton(tooltip: M.kaydet, icon: const Icon(Icons.check), onPressed: _kaydediyor ? null : _kaydet),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _anahtar,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Semantics(header: true, child: Text(_yeni ? M.etkinlikEkle : M.etkinligiDuzenle, style: tema.textTheme.headlineLarge)),
          ),
          if (_yeni) _turSecici(),
          if (_dogumGunu) ..._dogumGunuKartlari() else ...[
          _Kart(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextFormField(
                controller: _baslik,
                autofocus: _yeni,
                textCapitalization: TextCapitalization.sentences,
                decoration: _yalinAlan(M.baslik),
                validator: (s) => (s ?? '').trim().isEmpty ? M.baslikGerekli : null,
              ),
            ),
          ]),
          if (_buOrnek)
            Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text(M.sadeceBuOrnekIpucu, style: tema.textTheme.bodySmall)),
          _Kart(children: [
            if (!_buOrnek)
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                title: const Text(M.tumGun),
                value: _tumGun,
                onChanged: (b) => setState(() {
                  _tumGun = b;
                  if (b) {
                    _bas = gunDuvar(_bas);
                    _bit = gunDuvar(_bit).isBefore(_bas) ? _bas : gunDuvar(_bit);
                  } else {
                    _bas = DateTime.utc(_bas.year, _bas.month, _bas.day, 9);
                    _bit = _bas.add(const Duration(hours: 1));
                  }
                }),
              ),
            _ZamanSatiri(
              etiket: M.baslangic,
              tarih: _bas,
              saatGoster: !_tumGun,
              onTarih: () async {
                final t = await _tarihSec(_bas);
                if (t != null) _basDegistir(DateTime.utc(t.year, t.month, t.day, _bas.hour, _bas.minute));
              },
              onSaat: () async {
                final s = await _saatSec(_bas);
                if (s != null) _basDegistir(DateTime.utc(_bas.year, _bas.month, _bas.day, s.hour, s.minute));
              },
            ),
            _ZamanSatiri(
              etiket: M.bitis,
              tarih: _bit,
              saatGoster: !_tumGun,
              hata: _bitisHata,
              onTarih: () async {
                final t = await _tarihSec(_bit);
                if (t != null) setState(() => _bit = DateTime.utc(t.year, t.month, t.day, _bit.hour, _bit.minute));
              },
              onSaat: () async {
                final s = await _saatSec(_bit);
                if (s != null) setState(() => _bit = DateTime.utc(_bit.year, _bit.month, _bit.day, s.hour, s.minute));
              },
            ),
          ]),
          if (!_buOrnek) ...[
            _Kart(children: [
              _takvimSatiri(takvimler, takvim),
              ..._tekrarSatirlari(),
            ]),
            _hatirlaticiKarti(tema),
          ],
          _Kart(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextFormField(controller: _konum, decoration: _yalinAlan(M.konum, Icons.place_outlined)),
            ),
            if (!_buOrnek)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextFormField(
                  controller: _aciklama,
                  minLines: 2,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: _yalinAlan(M.aciklama, Icons.notes),
                ),
              ),
          ]),
          ],
        ]),
      ),
    );
  }

  Widget _takvimSatiri(List<Calendar> takvimler, Calendar? takvim) => _Satir(
        etiket: M.takvim,
        deger: takvim?.name ?? '',
        renk: takvim == null ? null : renkOku(takvim.color),
        onTap: () async {
          final u = await _secenekSec<String>([
            for (final c in takvimler) (c.uid, c.name, renkOku(c.color)),
          ], _takvimUid);
          if (u != null) setState(() => _takvimUid = u);
        },
      );

  /// Doğum günü: yıl kapalıyken seçici artık yılda açılır (29 Şubat seçilebilsin), yıl açıkken gelecek kapalı.
  Future<void> _dgTarihSec() async {
    final bugun = DateTime(k.bugun.year, k.bugun.month, k.bugun.day);
    var ilk = DateTime(_dgYilVar ? _dgTarih.year : 2024, _dgTarih.month, _dgTarih.day);
    if (_dgYilVar && ilk.isAfter(bugun)) ilk = bugun;
    final r = await showDatePicker(context: context, initialDate: ilk, firstDate: DateTime(1900), lastDate: _dgYilVar ? bugun : DateTime(2100));
    if (r != null && mounted) setState(() => _dgTarih = DateTime.utc(r.year, r.month, r.day));
  }

  List<Widget> _dogumGunuKartlari() => [
        _Kart(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextFormField(
              controller: _baslik,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: _yalinAlan(M.kisiAdi, Icons.cake_outlined),
              validator: (s) => (s ?? '').trim().isEmpty ? M.adGerekli : null,
            ),
          ),
        ]),
        _Kart(children: [
          _Satir(etiket: M.dogumTarihi, deger: _dgYilVar ? tarihTam(_dgTarih) : gunKisaMetin(_dgTarih), onTap: _dgTarihSec),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: const Text(M.dogumYiliBiliniyor),
            value: _dgYilVar,
            onChanged: (b) async {
              setState(() => _dgYilVar = b);
              if (b) await _dgTarihSec(); // varsayılan yıl (bu yıl) doğum yılı olamaz: hemen sor
            },
          ),
          _takvimSatiri(k.takvimlerSirali, k.takvimlerSirali.where((c) => c.uid == _takvimUid).firstOrNull),
        ]),
        _hatirlaticiKarti(Theme.of(context)),
      ];

  /// Yalnız yeni eklemede: Etkinlik | Doğum günü.
  Widget _turSecici() => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Semantics(
          label: M.turSecimi,
          child: SegmentedButton<bool>(
            style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(0, 48))),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.event_outlined), label: Text(M.turEtkinlik)),
              ButtonSegment(value: true, icon: Icon(Icons.cake_outlined), label: Text(M.turDogumGunu)),
            ],
            selected: {_dogumGunu},
            onSelectionChanged: (s) => setState(() => _dogumGunu = s.first),
          ),
        ),
      );

  /// Kartın içinde çizgisiz, dolgusuz giriş alanı.
  InputDecoration _yalinAlan(String etiket, [IconData? simge]) => InputDecoration(
        labelText: etiket,
        icon: simge == null ? null : Icon(simge),
        alignLabelWithHint: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
      );

  /// Alt sayfada seçenek listesi; (değer, metin, renk?) üçlüleri. İptalde null.
  Future<T?> _secenekSec<T>(List<(T, String, Color?)> secenekler, T secili) => showModalBottomSheet<T>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (c) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            for (final (d, m, renk) in secenekler)
              ListTile(
                minTileHeight: 48,
                leading: renk == null ? null : Container(width: 12, height: 12, decoration: BoxDecoration(color: renk, shape: BoxShape.circle)),
                title: Text(m, overflow: TextOverflow.ellipsis),
                trailing: d == secili ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(c, d),
              ),
          ]),
        ),
      );

  List<Widget> _tekrarSatirlari() {
    if (_ozelTekrar) {
      return [
        const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text(M.tekrarOzel)),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton(onPressed: () => setState(() { _ozelTekrar = false; _tekrar = const TekrarAyari(); }), child: const Text(M.tekrarYok)),
          ),
        ),
      ];
    }
    final etiket = {
      TekrarTuru.yok: M.tekrarYok,
      TekrarTuru.gunluk: M.tekrarGunluk,
      TekrarTuru.haftalik: M.tekrarHaftalik,
      TekrarTuru.aylik: M.tekrarAylik,
      TekrarTuru.yillik: M.tekrarYillik,
    };
    final bitisEtiket = {
      TekrarBitisi.hic: M.tekrarBitisHic,
      TekrarBitisi.tarih: M.tekrarBitisTarih,
      TekrarBitisi.sayi: M.tekrarBitisSayi,
    };
    return [
      _Satir(
        etiket: M.tekrar,
        deger: etiket[_tekrar.tur]!,
        onTap: () async {
          final t = await _secenekSec<TekrarTuru>([for (final t in TekrarTuru.values) (t, etiket[t]!, null)], _tekrar.tur);
          if (t != null) setState(() => _tekrar = _tekrar.kopya(tur: t));
        },
      ),
      if (_tekrar.tur == TekrarTuru.haftalik)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(spacing: 6, runSpacing: 4, children: [
            for (var g = 1; g <= 7; g++)
              Semantics(
                label: M.gunAdlari[g - 1],
                child: FilterChip(
                  label: Text(M.gunTek[g - 1]),
                  tooltip: M.gunAdlari[g - 1],
                  showCheckmark: false,
                  // Başlangıç günü her zaman seçili (RFC 5545: DTSTART kuralla uyuşmalı).
                  selected: g == _bas.weekday || _ekGunler.contains(g),
                  onSelected: g == _bas.weekday ? null : (s) => setState(() => s ? _ekGunler.add(g) : _ekGunler.remove(g)),
                ),
              ),
          ]),
        ),
      if (_tekrar.tur != TekrarTuru.yok) ...[
        _Satir(
          etiket: M.bitis,
          deger: bitisEtiket[_tekrar.bitis]!,
          onTap: () async {
            final b = await _secenekSec<TekrarBitisi>([for (final b in TekrarBitisi.values) (b, bitisEtiket[b]!, null)], _tekrar.bitis);
            if (b != null) setState(() => _tekrar = _tekrar.kopya(bitis: b, bitisGunu: _tekrar.bitisGunu ?? gunEkle(gunDuvar(_bas), 30)));
          },
        ),
        if (_tekrar.bitis == TekrarBitisi.tarih)
          _Satir(
            etiket: '${M.tekrarBitisTarihiSec}: ${tarihTam(_tekrar.bitisGunu ?? _bas)}',
            onTap: () async {
              final t = await _tarihSec(_tekrar.bitisGunu ?? _bas);
              if (t != null) setState(() => _tekrar = _tekrar.kopya(bitisGunu: t));
            },
          ),
        if (_tekrar.bitis == TekrarBitisi.sayi)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextFormField(
              controller: _sayi,
              keyboardType: TextInputType.number,
              decoration: _yalinAlan(M.tekrarSayi),
              validator: (s) => (int.tryParse((s ?? '').trim()) ?? 0) < 1 ? M.sayiGecersiz : null,
            ),
          ),
      ],
    ];
  }

  Set<int> get _aktifHat => _dogumGunu ? _dgHat : _hat;

  Widget _hatirlaticiKarti(ThemeData tema) {
    final sirali = _aktifHat.toList()..sort();
    return _Kart(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true, child: Text(M.hatirlaticilar, style: tema.textTheme.bodyLarge)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final m in sirali)
              InputChip(
                avatar: const Icon(Icons.notifications_none, size: 18),
                label: Text(_tumGun || _dogumGunu ? M.tumGunHatirlaticiMetni(m) : M.hatirlaticiMetni(m)),
                deleteButtonTooltipMessage: M.sil,
                onDeleted: () => setState(() => _aktifHat.remove(m)),
              ),
            ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text(M.hatirlaticiEkle), onPressed: _hatirlaticiSec),
          ]),
        ]),
      ),
    ]);
  }

  Future<void> _hatirlaticiSec() async {
    final secim = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final m in _dogumGunu ? _dogumHatirlaticiSecenekleri : _hatirlaticiSecenekleri)
            ListTile(title: Text(_tumGun || _dogumGunu ? M.tumGunHatirlaticiMetni(m) : M.hatirlaticiMetni(m)), onTap: () => Navigator.pop(c, m)),
          ListTile(title: const Text(M.ozelHatirlatici), onTap: () => Navigator.pop(c, -1)),
        ]),
      ),
    );
    if (secim == null || !mounted) return;
    if (secim >= 0) {
      setState(() => _aktifHat.add(secim));
      return;
    }
    final dk = await showDialog<int>(context: context, builder: (c) => const _DakikaSor());
    if (dk != null && mounted) setState(() => _aktifHat.add(dk));
  }
}

/// Yuvarlak köşeli koyu kart grubu (ay görünümündeki kart diliyle aynı).
class _Kart extends StatelessWidget {
  const _Kart({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        // Material: içteki ListTile/InkWell sıçramaları kart zemininin üstünde görünsün.
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      );
}

/// Solda etiket, sağda değer ve ">" olan dokunulabilir satır (en az 56 px).
class _Satir extends StatelessWidget {
  const _Satir({required this.etiket, required this.onTap, this.deger, this.renk});
  final String etiket;
  final String? deger;
  final Color? renk;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final soluk = tema.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: deger == null ? etiket : '$etiket, $deger',
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            child: Row(children: [
              Text(etiket, style: tema.textTheme.bodyLarge),
              Expanded(
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (renk != null) ...[
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: renk, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                  ],
                  if (deger != null) Flexible(child: Text(deger!, overflow: TextOverflow.ellipsis, style: tema.textTheme.bodyMedium?.copyWith(color: soluk))),
                ]),
              ),
              Icon(Icons.chevron_right, color: soluk),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ZamanSatiri extends StatelessWidget {
  const _ZamanSatiri({required this.etiket, required this.tarih, required this.saatGoster, required this.onTarih, required this.onSaat, this.hata});
  final String etiket;
  final DateTime tarih;
  final bool saatGoster;
  final VoidCallback onTarih;
  final VoidCallback onSaat;
  final String? hata;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final soluk = tema.colorScheme.onSurfaceVariant;
    final deger = tema.textTheme.bodyMedium?.copyWith(color: soluk);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(etiket, style: tema.textTheme.bodyLarge)),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(0, 56), foregroundColor: soluk, padding: const EdgeInsets.symmetric(horizontal: 6)),
            onPressed: onTarih,
            child: Text('${tarih.day} ${M.ayKisa[tarih.month - 1]} ${tarih.year} ${M.gunKisa[tarih.weekday - 1]}', style: deger),
          ),
          if (saatGoster)
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 56), foregroundColor: soluk, padding: const EdgeInsets.symmetric(horizontal: 6)),
              onPressed: onSaat,
              child: Text(saatMetni(tarih), style: deger),
            ),
          Icon(Icons.chevron_right, color: soluk),
        ]),
        if (hata != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(hata!, style: TextStyle(color: tema.colorScheme.error, fontSize: 12))),
      ]),
    );
  }
}

class _DakikaSor extends StatefulWidget {
  const _DakikaSor();
  @override
  State<_DakikaSor> createState() => _DakikaSorDurumu();
}

class _DakikaSorDurumu extends State<_DakikaSor> {
  final _c = TextEditingController(text: '30');
  String? _hata;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(M.ozelHatirlaticiBaslik),
      content: TextField(
        controller: _c,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: M.dakika, errorText: _hata),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(M.iptal)),
        FilledButton(
          onPressed: () {
            final n = int.tryParse(_c.text.trim());
            if (n == null || n < 0) {
              setState(() => _hata = M.sayiGecersiz);
              return;
            }
            Navigator.pop(context, n);
          },
          child: const Text(M.tamam),
        ),
      ],
    );
  }
}
