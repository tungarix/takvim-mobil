# Takvim (Android)

Takvim'in Android (Flutter) sürümü. Çevrimdışı, hesapsız, ağ erişimi yok. Masaüstü
sürümüyle `.takvimsync` dosyası üzerinden veri alışverişi yapar; biçim ve birleştirme
kuralları masaüstü deposundaki `docs/senkron.md` belgesindedir (bağlayıcı).

Bu aşamada yalnızca veri katmanı ve senkron mantığı var; arayüz sonraki aşama.

## Yapı

- `lib/core/` saf Dart (Flutter'a ve `store/`a bağlı değil): modeller, tekrar açılımı
  (`recurrence.dart`), hatırlatıcılar, bellekteki durum ve mutasyon kuralları (`veri.dart`).
- `lib/store/` kalıcılık: tek JSON dosyası, atomik yazma, bozulmada son sağlam yedeğe dönüş.
- `lib/sync/` `export.dart` (tam durum) ve `import.dart` (birleştirme, rapor).
- `test/` birim testleri; `test/uyum_test.dart` açılımı masaüstü çıktısıyla birebir karşılaştırır.
- `tool/uyum_uret.py` uyum fixture'ını masaüstü açıcısından üretir (masaüstü deposu okunur, değişmez).

## Komutlar

    flutter analyze
    flutter test
