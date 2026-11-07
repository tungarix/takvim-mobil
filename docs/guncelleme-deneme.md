# Güncelleme denemesi (emülatör, uçtan uca)

Kotlin `PackageInstaller` yolu yalnızca gerçek Android'de sınanabilir. Yöntem (0.4.0 hazırlığında denendi, geçti):

1. İki APK derle, aynı anahtarla imzalı, sürüm kodu farklı:
   `flutter build apk --release --target-platform android-x64 --dart-define=GUNCELLEME_TABAN=http://10.0.2.2:8123
   --dart-define=GUNCELLEME_MAKS_BAYT=400000000 --build-name=0.3.0 --build-number=3` ve aynısı `0.4.0` / `4`.
   (Ana manifestte `usesCleartextTraffic` bu deneme boyunca geçici olarak `true` yapılır, sonra geri alınır; `GUNCELLEME_*`
   tanımları yalnız bu derlemede verilir, `release.yml` hiç vermez. NDK araçları eksik makinede sembol temizleme
   atlanır, APK büyük çıkar: bu yüzden boyut sınırı tanımı.)
2. Sahte GitHub: `python tool/e2e/guncelleme_sahte_github.py [kotu] <yeni.apk klasörü>` (`kotu` = yanlış özet).
3. Emülatörde eski APK'yı kur, uygulamayı aç: ilk açılış sorusu → Evet → Ayarlar → Güncellemeler → kur →
   (izin yoksa Android ayar ekranı) → indirme → sistemin "güncelle?" penceresi → sürüm yükselir, ayarlar korunur.

Doğrulananlar: soru yanıtlanmadan 0 istek; geri tuşu soruyu kapatmaz; "Evet" sonrası 1 istek; izin yokken indirme yok
ve Android'in "bilinmeyen uygulamaları yükle" ekranı açılır; ölçülü ağda ayrı onay; SHA256SUMS → APK indirme;
sistem kurulum penceresi; 0.3.0 (kod 3) → 0.4.0 (kod 4); güncelleme sonrası soru yeniden çıkmaz.
