# Takvim (Android)

Takvim'in Android (Flutter) sürümü. Çevrimdışı, hesapsız, ağ erişimi yok (release manifest'inde
`INTERNET` izni yoktur). Masaüstü sürümüyle `.takvimsync` dosyası üzerinden veri alışverişi yapar;
biçim ve birleştirme kuralları masaüstü deposundaki `docs/senkron.md` belgesindedir (bağlayıcı).

Veriler yalnız bu telefonda tutulur (`allowBackup=false`: bulut yedeğine de gitmez).

## Özellikler

- Material 3, sistem açık/koyu temasını izler; telefon dikey öncelikli, tablet de çalışır.
- Alt gezinme: **Takvim** (Gün / Hafta / Ay), **Görevler**, **Ayarlar**.
- Gün ve hafta saat ızgarası (çakışanlar yan yana, tüm gün şeridi, şimdi çizgisi), ay görünümü
  (telefonda noktalar, geniş ekranda başlıklı şeritler). Boş saate dokununca o saatte yeni etkinlik.
- Etkinlik: başlık, takvim, tüm gün, başlangıç/bitiş, konum, açıklama, tekrar (her gün/hafta/ay/yıl,
  hafta günleri, bitiş: hiç/tarih/n kez), çoklu hatırlatıcı. Tekrarlı etkinlikte sil/düzenle:
  **yalnız bu** (override), **bu ve sonrakiler** (seri bölme), **tümü**. Silmede tek adım geri al.
- Görevler: plansız / bugün / planlı; satır içi ekleme, tamamlama, düzenleme, güne ya da saate
  planlama (saate planlanan görev takvimde zaman bloğu olur), silme (geri alınabilir).
- Takvimler: ekle, yeniden adlandır, renk, görünür/gizli, sil (içindeki etkinlikler de gider).
  İlk açılışta varsayılan "Kişisel" takvimi oluşur (senkronda ad eşleşmesi buna bağlı).
- Arama: etkinlik başlığı/açıklaması/konumu ve görevler; Türkçe harfler katlanır ("carsamba" = "Çarşamba").
- Hatırlatıcılar: yerel bildirim; önümüzdeki 14 gün ve en çok 60 bildirim planlanır, her veri
  değişiminde, açılışta ve arka plandan dönüşte yeniden kurulur, cihaz yeniden başlayınca da yeniden kurulur.

## Masaüstüyle senkron

Ayarlar > **Masaüstüyle senkron**:

1. **Senkron dosyası gönder**: tam durum `takvim-YYYYMMDD-SSDD.takvimsync` olarak sistem Paylaş
   menüsüne gider (WhatsApp, Drive, e-posta, kablo...). Masaüstünde bu dosyayı içe aktarın.
2. **Senkron dosyası aç**: dosya seçicisinden `.takvimsync` seçin. Ya da dosya yöneticisinde /
   WhatsApp'ta / Drive'da dosyaya dokunun ve **Takvim**'i seçin (uygulama bunun için "Birlikte aç" ve
   "Paylaş" hedefi olarak kayıtlıdır).
3. Önce **önizleme** çıkar ("N etkinlik, M görev, K silme; mevcut veriyle birleşecek"), onaylarsanız
   içe aktarılır ve sonuç özeti ({eklenen, güncellenen, silinen, atlanan}) gösterilir.

Birleştirme güvenlidir: yalnızca daha yeni kayıtlar uygulanır, aynı dosya ikinci kez açılırsa değişen
bir şey olmaz. Bozuk dosya ya da uygulamadan yeni bir sürümle yazılmış dosya anlaşılır bir mesajla
reddedilir ve veri hiç değişmez. Son senkron zamanı Ayarlar'da görünür.

## Masaüstü <-> mobil uçtan uca doğrulama

Tek komut (mobil kökünden; `dart` PATH'te ve masaüstü deposunda `.venv` kurulu olmalı):

    powershell -File tool/e2e/calistir.ps1                  # her şey (~30 sn)
    powershell -File tool/e2e/calistir.ps1 -Senaryo a,f     # seçili senaryolar: a,b,c,d,e,olcek,f

Masaüstü kodu (`takvim/senkron`, `takvim/store`) GEÇİCİ SQLite dosyasıyla, mobil kodu (`lib/core`,
`lib/sync`, `lib/store`) GEÇİCİ JSON deposuyla sürülür (`tool/e2e/mobil_sunucu.dart`); ikisinin
arasında yalnızca `.takvimsync` dosyaları geçer. Gerçek `%LOCALAPPDATA%` veritabanına ve telefon
verisine dokunulmaz. `flutter test` kullanılmaz.

Mobil saati gerçek saatten `ofset(saniye)` ile kaydırılabilir (masaüstü SQLite tetikleyicileriyle gerçek
saati kullanır): "mobil sonra düzenledi" = +600 sn, "masaüstü sonra" = -600 sn.

Senaryolar (her biri iki cihazın dosya olarak dışa aktarılan TAM durumunu karşılaştırır: takvim/etkinlik/görev
uid kümeleri, bütün alanlar, silinenler, ve tekrar açılımı pencereleri):

- **a** masaüstünde başla (tekrarlı + override + hatırlatıcı + görev + saat planlı görev) -> mobil ->
  mobilde düzenle/tamamla/sil/ekle -> masaüstü -> ikinci dalga -> eşit.
- **b** LWW iki yön ve iki içe aktarma sırası; düzenle-vs-sil (etkinlik/görev, iki yön, iki zaman sırası);
  takvim silme (CASCADE, yetim etkinlik, eski silme); silip geri al.
- **c** iki cihazda bağımsız "Kişisel" takvimi ad eşleşmesiyle birleşir (sırayla ve eşzamanlı çapraz dosya), çift takvim olmaz.
- **d** aynı dosyayı iki kez içe aktar (değişiklik yok, depo birebir aynı), ping-pong ve silme yankısı yok.
- **e** Türkçe/emoji, tzid çeşitleri (takma adlar dahil), tüm gün, DST öncesi/sonrası, boş/null alanlar,
  10 bin karakter, çeşitli RRULE'lar; iki yönde.
- **olcek** 2000 etkinlik / 500 görev (ve 4000/1000) iki yönde, adım süreleri raporlanır; her adım 15 sn'den kısa olmalı.
- **f** bozuk/eksik/yanlış tipli/yinelenen uid'li/yeni sürümlü/farklı uzantılı/BOM'lu dosyalar: iki taraf
  anlaşılır hata verir ve veri hiç değişmez; geçerli ama farklı biçimli dosyalar iki tarafta aynı sonucu verir.

`tool/e2e/mobil_regresyon.dart` (`dart run`) e2e'nin bulduğu mobil hatalar için saf Dart regresyon
denetimleridir. `tool/tz_takma_adlar_uret.py`, `lib/core/tz_takma_adlar.dart` tablosunu üretir
(`timezone` paketinin bilmediği IANA takma adları: `UTC`, `Europe/Amsterdam`, `Asia/Calcutta`...).

## Yapı

- `lib/core/` saf Dart (Flutter'a ve `store/`a bağlı değil): modeller, tekrar açılımı
  (`recurrence.dart`), seri bölme (`seri_bol.dart`), tekrar formu <-> RRULE (`tekrar.dart`), çakışma
  yerleşimi (`yerlesim.dart`), arama, bildirim planı, hatırlatıcılar, bellekteki durum ve mutasyon
  kuralları (`veri.dart`).
- `lib/store/` kalıcılık: tek JSON dosyası, atomik yazma, bozulmada son sağlam yedeğe dönüş
  (`takvim_store.dart`); küçük cihaz ayarları (`ayarlar.dart`).
- `lib/sync/` `export.dart` (tam durum) ve `import.dart` (birleştirme, rapor).
- `lib/platform/` Android'e bağlanan ince katman: bildirimler, dosya seç/paylaş, MainActivity köprüsü.
- `lib/app/kontrol.dart` tek durum nesnesi (ChangeNotifier); tüm yazmalar `yap` kapısından geçer.
- `lib/ui/` ekranlar (ekran başına bir dosya). Tüm arayüz metinleri `lib/ui/metin.dart`'ta
  (İngilizce sürüm için tek çeviri noktası).
- `test/` birim ve widget testleri; `test/uyum_test.dart` ve `test/uyum_masaustu_test.dart` açılımı
  masaüstü çıktısıyla (fixture) birebir karşılaştırır. `tool/uyum_uret.py` uyum fixture'ını
  masaüstü açıcısından üretir (masaüstü deposu okunur, değişmez).
- `android/` manifest (izinler, `.takvimsync` intent filtreleri, bildirim alıcıları) ve
  `MainActivity.kt` (saat dilimi + gelen dosya köprüsü).

## Kurulum ve derleme

Gereksinimler: Flutter 3.47+, Android SDK (platform 36, build-tools 36.0.0), Android cihaz ya da emülatör.

    flutter pub get
    flutter analyze
    flutter test
    flutter run                      # bağlı cihaz/emülatör
    flutter build apk --debug
    flutter build apk --release      # şimdilik debug anahtarıyla imzalanır; yayın imzası bu aşamada yok

Sürüm tek yerde: `lib/surum.dart` (`test/cekirdek_ek_test.dart` bunun `pubspec.yaml` ile aynı olduğunu doğrular).

## İzinler

- `POST_NOTIFICATIONS` (Android 13+): bildirim göstermek için; ilk hatırlatıcıda istenir, Ayarlar'dan da verilebilir.
- `USE_EXACT_ALARM` / `SCHEDULE_EXACT_ALARM` (yalnız Android 12): hatırlatıcı tam zamanında çalsın.
  İzin yoksa uygulama çökmez, bildirimler yaklaşık zamanda gelir ve Ayarlar'da uyarı görünür.
- `RECEIVE_BOOT_COMPLETED`: cihaz yeniden başlayınca alarmlar yeniden kurulsun.

## Bilinen sınırlar

- Hafta görünümünde telefonda (<600 dp) 3 gün görünür, yatay kaydırılır; önceki/sonraki hafta ok
  düğmeleriyle (gün ve ay görünümünde yana kaydırma da çalışır).
- Saat ızgarası duvar saatiyle çizilir; yaz saati geçiş gününde tekrarlayan saat ayrı gösterilmez
  (Türkiye'de yaz saati yok).
- Etkinlik formu telefonun saat dilimini kullanır; başka saat diliminde oluşturulmuş etkinliklerde
  tekrar kuralı kendi saat diliminde açılır, ekranda cihaz saatiyle görünür.
- Dosya yöneticisinden açma `content://` adreslerini destekler (Android 11+ kapsamlı depolama);
  `file://` ile gelen eski yönlendirmeler okunamayabilir, o durumda Ayarlar'dan dosya seçin.
- Özel (başka cihazda ayarlanmış, örn. `INTERVAL`) tekrar kuralları forma sığmaz: olduğu gibi korunur,
  yalnızca "tekrarsız yap" seçilebilir.
- Hatırlatıcılar 14 günlük pencerede planlanır; uygulama 14 günden uzun açılmazsa o sürenin
  ötesindeki hatırlatıcılar bir sonraki açılışta kurulur.
- Yalnız Türkçe arayüz (metinler tek dosyada, çeviriye hazır).

## Testleri çalıştırma (Windows uyarısı)

Bu geliştirme makinesinde `flutter_tester` motoru rastgele `0xC0000005` (erişim ihlali) ile çöküyor;
süreç ölünce kalan testler mesajsız "did not complete" olur ve `flutter test` kırmızı biter. Bu
Takvim'e özgü değil: dokunulmamış kardeş proje `dosya-dolabi`'nde de 4/4 koşuda aynı çökme olur,
yalnızca `pumpWidget(SizedBox())` yapan boş bir test dosyası da zaman zaman çöker. Çökme gerçek
kare çizen (yeni sahne üreten) pump sayısıyla artar. Çözüm motor tarafında olduğundan testler
gevşetilmedi; bunun yerine:

- Testler küçük dosyalara bölündü (her dosya ayrı süreç, çökme alanı daralır).
- `tool/test_calistir.ps1` her dosyayı ayrı çalıştırır; yalnızca çökme imzası (başka hata metni
  olmadan "did not complete") görülürse o dosyayı yeniden dener. Gerçek test hatası yeniden denenmez.

      powershell -File tool/test_calistir.ps1

Düz `flutter test` bu makinede çoğu zaman çökme yüzünden kırmızı biter; CI'da (çökmenin
görülmediği ortam) olduğu gibi çalışır.

## Lisans

MIT (bkz. `LICENSE`).
