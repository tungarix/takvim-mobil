# Katkıda bulunma

Takvim (Android)'e baktığın için sağ ol. Hata bildirimi, küçük düzeltme ve gerekçesi olan öneri
hoş karşılanır. Katılırken [Davranış Kuralları](CODE_OF_CONDUCT.md)'na uymayı kabul edersin.
Güvenlik sorunları herkese açık issue'ya değil, [SECURITY.md](SECURITY.md)'deki özel kanala gider.

## Kod yazmadan önce

- Yazım hatası ya da bariz bir hata düzeltmesinden büyük her şey için **önce issue aç**.
- **Kapsam bir karardır.** Bilerek kapsam dışı: sunucu ya da hesap, otomatik bulut senkronu,
  katılımcı / davet / RSVP, CalDAV. Uygulamada `INTERNET` izni olmayacak; bunu isteyen bir pull
  request kod ne kadar iyi olursa olsun kabul edilmez.
- Hata bildiriminde issue formunu kullan, sürümünü ve Android sürümünü yaz. **Kendi takvim verini
  ya da `.takvimsync` dosyanı asla ekleme.**
- Senkron dosya biçimi masaüstü Takvim ile ortaktır ve bağlayıcı belge masaüstü deposundaki
  [`docs/senkron.md`](https://github.com/tungarix/takvim/blob/master/docs/senkron.md)'dir; biçime
  dokunan değişiklik iki tarafta birden yapılmalı.

## Kurulum

Flutter 3.47, JDK 17+, Android SDK. Ayrıntılar README'nin "Derleme" bölümünde.

```bash
flutter pub get
flutter analyze
flutter test
```

CI (`ci.yml`) bu ikisini her push'ta ve pull request'te çalıştırır; pull request'in ikisini de
geçmeli. Windows'ta `flutter test` motor çökmesi yüzünden rastgele kırmızı bitebilir
(README "Testleri çalıştırma"); `powershell -File tool/test_calistir.ps1` her dosyayı ayrı koşar.

## Kurallar

- `lib/core/` saf Dart'tır: Flutter'a ve `lib/store/`a bağlı değildir. Tersi serbest.
- Modeller değişmezdir (`copyWith`), doğrulama kurucudadır. "Sonra kontrol ederiz" yok.
- Yorumlar ve test adları Türkçe; yorum *neden*'i anlatır, *ne*'yi değil.
- Yeni davranışın kendi testi olur. Dışarıdan gelen veriyi (dosya, intent) işleyen yer
  güvenilmeyen girdiye karşı denenir (bozuk, çok büyük, çok derin, kötü niyetli).
- Arayüz metinleri `lib/ui/metin.dart`'ta toplanır.
- Sürüm `pubspec.yaml` ve `lib/surum.dart`'ta aynı olur.

## Pull request'ler

- Küçük ve tek konulu tut. İlgili issue'yu bağla.
- `*.jks`, parola, `.takvimsync` ya da kişisel veri commit'leme.
- Katkıda bulunarak çalışmanın [MIT Lisansı](LICENSE) ile yayımlanmasını kabul edersin.
