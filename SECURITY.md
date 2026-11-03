# Güvenlik Politikası

Takvim (Android) hesapsız ve sunucusuz çalışır; internet servislerine bağlanmaz. `INTERNET` izni yalnız
"Wi-Fi ile eşleştir" özelliği içindir: yalnız sen başlatınca, aynı yerel ağdaki (özel IP adresli)
masaüstü Takvim'e, sertifika parmak iziyle sabitlenmiş HTTPS ile bağlanır; başka hiçbir ağ isteği yoktur
(ayrıntı README'de). Verin yalnız telefonundaki uygulama klasöründe durur ve bulut yedeğine gitmez
(`allowBackup=false`). Bu saldırı yüzeyini küçültür ama sıfırlamaz: uygulama dışarıdan gelen
`.takvimsync` dosyalarını okur (dosya seçici, "Birlikte aç", Paylaş menüsü) ve eşleştirme
bağlantılarını (`https://aktenak.tech/s#...`, yalnız onay ekranını açar), yerel bildirim kurar ve
dosyayı sistem Paylaş menüsüne verir.

## Desteklenen sürümler

Güvenlik düzeltmeleri yalnızca [son sürüme](https://github.com/tungarix/takvim-mobil/releases/latest)
gelir. Eski bir sürümdeysen önce güncelle, sorun hâlâ varsa bildir.

## Açık bildirme

**Güvenlik sorunu için lütfen herkese açık issue açma.**

GitHub'ın özel bildirimini kullan:
**[Güvenlik açığı bildir](https://github.com/tungarix/takvim-mobil/security/advisories/new)**
(depo → *Security* sekmesi → *Report a vulnerability*). Bildirimi yalnızca bakımcı görür.

Şunları yazarsan işim kolaylaşır:

- Takvim sürümü (Ayarlar'ın en altında "Sürüm X.Y.Z" yazar), Android sürümü ve cihaz,
- ne yaptın, ne bekledin, ne oldu,
- sence etkisi ne (saldırgan neyi okuyabilir, değiştirebilir, bozabilir),
- gerekiyorsa sorunu yeniden üreten küçük, uydurma bir `.takvimsync` dosyası.

**Kendi takvim verini ya da gerçek kişisel veri içeren dosya EKLEME.**

Bu tek kişilik bir proje; yanıt vermek elimden geldiği kadar. Yaklaşık bir hafta içinde cevap
vermeye, istemezsen adını yazmamak koşuluyla sürüm notlarında sana teşekkür etmeye çalışırım.

## Neler kapsamda

Örneğin: hazırlanmış bir `.takvimsync` dosyasının uygulamayı dondurması, çökertmesi ya da verini
bozması; uygulamanın kendi özel dosyalarını başka bir uygulamaya sızdıran bir intent/paylaşım yolu;
dışarıdan gelen bir intent'in kullanıcı onayı olmadan veri değiştirmesi; Wi-Fi eşleştirmede bağlantı
doğrulamasının atlatılıp telefonun özel/yerel ağ dışına ya da parmak izi uyuşmayan bir sunucuya bağlanması
veya verinin ikinci onaydan önce gönderilmesi; yayımlanan özet,
attestation ya da sertifika parmak iziyle uyuşmayan bir APK.

## Neler kapsam dışı

- Telefonun kilidini açık tutan ya da telefona root/adb erişimi olan biri. Veri uygulama klasöründe
  düz bir JSON dosyasıdır; cihazın kendi korumasına (ekran kilidi, depolama şifrelemesi) güvenir.
- Bildirimlerin kilit ekranında görünmesi: bu Android'in kilit ekranı bildirim ayarına bağlıdır.
- Play Protect'in "tanınmayan uygulama" uyarısı: APK Google Play'de yayımlanmıyor.
- Yalnızca kendi derlediğin ya da değiştirdiğin bir sürümde görülen sorunlar.

## İndirmeyi doğrulama

Her sürümde `SHA256SUMS.txt`, GitHub build provenance attestation'ı ve sabit bir imza sertifikası
vardır. Adımlar: [README](README.md#indirmeyi-doğrula).

## Sürüm incelemeleri

Her sürüm yayımlanmadan önce güvenlik açısından incelenir ve kaydı
[`guvenlik/incelemeler/`](guvenlik/incelemeler/) altında tutulur; kaydı olmayan sürüm derlenmez.
