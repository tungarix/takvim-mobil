// Arayüz metinlerinin TEK yeri. İngilizce sürüm eklenirken yalnızca bu dosya
// (ve gün/ay adı dizileri) çevrilir; ekranlar metin yazmaz, buradan okur.
//
// Kural: kullanıcı verisi (etkinlik/takvim adı) buraya girmez; yalnız arayüz metni.
import '../sync/import.dart';
import '../sync/wifi_baglanti.dart';
import '../sync/wifi_istemci.dart';

class M {
  const M._();

  // --- genel
  static const uygulamaAdi = 'Takvim';
  static const tamam = 'Tamam';
  static const iptal = 'İptal';
  static const kaydet = 'Kaydet';
  static const sil = 'Sil';
  static const duzenle = 'Düzenle';
  static const ekle = 'Ekle';
  static const geriAl = 'Geri al';
  static const kapat = 'Kapat';
  static const bugun = 'Bugün';
  static const yarin = 'Yarın';
  static const tumGun = 'Tüm gün';
  static const baslikGerekli = 'Başlık gerekli';
  static String hata(Object e) => 'Hata: $e';
  static String kaydedilemedi(Object e) => 'Kaydedilemedi, veri değişmedi: $e';

  // --- gezinme
  static const sekmeTakvim = 'Takvim';
  static const sekmeGorevler = 'Görevler';
  static const sekmeAyarlar = 'Ayarlar';
  static const gorunumGun = 'Gün';
  static const gorunumHafta = 'Hafta';
  static const gorunumAy = 'Ay';
  static const onceki = 'Önceki';
  static const sonraki = 'Sonraki';
  static const ara = 'Ara';
  static const yeniEtkinlik = 'Yeni etkinlik';
  static const etkinlikEkle = 'Etkinlik ekle';

  // --- gün adları (Pazartesi ilk)
  static const gunAdlari = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
  static const gunKisa = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
  static const gunTek = ['P', 'S', 'Ç', 'P', 'C', 'C', 'P'];
  static const ayAdlari = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
  ];
  static const ayKisa = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];

  // --- etkinlik formu
  static const baslik = 'Başlık';
  static const takvim = 'Takvim';
  static const baslangic = 'Başlangıç';
  static const bitis = 'Bitiş';
  static const konum = 'Konum';
  static const aciklama = 'Açıklama';
  static const tekrar = 'Tekrar';
  static const hatirlaticilar = 'Hatırlatıcılar';
  static const hatirlaticiEkle = 'Hatırlatıcı ekle';
  static const ozelHatirlatici = 'Özel…';
  static const ozelHatirlaticiBaslik = 'Kaç dakika önce?';
  static const dakika = 'Dakika';
  static const bitisHataliEtkinlik = 'Bitiş, başlangıçtan sonra olmalı';
  static const takvimYok = 'Önce bir takvim oluşturun';
  static const tekrarYok = 'Tekrarlanmaz';
  static const tekrarGunluk = 'Her gün';
  static const tekrarHaftalik = 'Her hafta';
  static const tekrarAylik = 'Her ay';
  static const tekrarYillik = 'Her yıl';
  static const tekrarOzel = 'Özel tekrar (başka bir cihazda ayarlanmış; olduğu gibi korunur)';
  static const tekrarBitisHic = 'Hiç bitmesin';
  static const tekrarBitisTarih = 'Tarihte bitsin';
  static const tekrarBitisSayi = 'Şu kadar tekrar';
  static const tekrarSayi = 'Tekrar sayısı';
  static const tekrarBitisTarihiSec = 'Bitiş tarihi';
  static const sayiGecersiz = '1 veya daha büyük bir sayı girin';
  static const sadeceBuOrnekIpucu = 'Yalnızca bu örnek değişir: başlık, saat ve konum.';
  static String kayitHatasi(Object e) => 'Etkinlik kaydedilemedi: $e';
  static String hatirlaticiMetni(int dk) {
    if (dk == 0) return 'Başladığında';
    String birim(int n, String b) => '$n $b önce';
    if (dk % 10080 == 0) return birim(dk ~/ 10080, 'hafta');
    if (dk % 1440 == 0) return birim(dk ~/ 1440, 'gün');
    if (dk % 60 == 0) return birim(dk ~/ 60, 'saat');
    return birim(dk, 'dakika');
  }

  // --- kapsam (tekrarlı düzenleme/silme)
  static const kapsamDuzenleBaslik = 'Tekrarlı etkinliği düzenle';
  static const kapsamSilBaslik = 'Tekrarlı etkinliği sil';
  static const kapsamBuOrnek = 'Yalnızca bu etkinlik';
  static const kapsamBuVeSonrakiler = 'Bu ve sonrakiler';
  static const kapsamTumu = 'Tüm seri';
  static const kapsamSilBilgi = 'Silmek için kapsamı seçin.';
  static const kapsamDuzenleBilgi = 'Değişiklik hangi etkinliklere uygulansın?';

  // --- etkinlik silme / geri alma
  static String etkinlikSilindi(String baslik) => '"$baslik" silindi';
  static const ornekSilindi = 'Bu etkinlik silindi';
  static const sonrakilerSilindi = 'Bu ve sonrakiler silindi';
  static const seriSilindi = 'Tüm seri silindi';
  static const geriAlindi = 'Geri alındı';

  // --- etkinlik ayrıntı
  static const hatirlatici = 'Hatırlatıcı';
  static const tekrarlanir = 'Tekrarlanır';
  static const gorevBlogu = 'Görev bloğu';
  static String saatAraligi(String bas, String bit) => '$bas – $bit';

  // --- görevler
  static const gorevEkleIpucu = 'Görev ekle…';
  static const gorevEkleAria = 'Görevi ekle';
  static const gorevBugun = 'Bugün';
  static const gorevPlansiz = 'Plansız';
  static const gorevPlanli = 'Planlı';
  static const gorevTamamlanan = 'Tamamlananlar';
  static const gorevBos = 'Henüz görev yok. Yukarıya yazıp ekleyin.';
  static const gorevBosBolum = 'Görev yok';
  static const gorevDuzenleBaslik = 'Görevi düzenle';
  static const gorevNot = 'Not';
  static const gorevGuneP = 'Güne planla';
  static const gorevSaateP = 'Saate planla';
  static const gorevBugunePlanla = 'Bugüne planla';
  static const gorevPlaniKaldir = 'Planı kaldır';
  static const gorevTamamla = 'Tamamlandı olarak işaretle';
  static const gorevYenidenAc = 'Yeniden aç';
  static String gorevSilindi(String baslik) => 'Görev silindi: $baslik';
  static String gorevKutuAria(String baslik, bool bitti) => bitti ? 'Yeniden aç: $baslik' : 'Tamamla: $baslik';
  static const saatPlanBaslik = 'Saate planla';
  static const sure = 'Süre';
  static const gun = 'Gün';
  static const saat = 'Saat';
  static String sureMetni(int dk) {
    if (dk < 60) return '$dk dk';
    if (dk % 60 == 0) return '${dk ~/ 60} sa';
    return '${dk ~/ 60} sa ${dk % 60} dk';
  }

  // --- takvimler
  static const takvimler = 'Takvimler';
  static const takvimEkle = 'Takvim ekle';
  static const takvimAd = 'Takvim adı';
  static const takvimRenk = 'Renk';
  static const takvimDuzenle = 'Takvimi düzenle';
  static const takvimAdBos = 'Ad boş olamaz';
  static const takvimAdVar = 'Bu adda bir takvim zaten var';
  static const sonTakvimSilinemez = 'Son takvim silinemez';
  static const takvimGorunur = 'Görünür';
  static String takvimSilOnay(String ad, int etkinlikSayisi) =>
      '"$ad" takvimi silinecek. İçindeki $etkinlikSayisi etkinlik de silinir. Bu işlem geri alınamaz.';
  static const takvimSilBaslik = 'Takvimi sil';
  static String takvimSilindi(String ad) => 'Takvim silindi: $ad';

  // --- arama
  static const aramaIpucu = 'Etkinlik veya görev ara';
  static const aramaBos = 'Sonuç yok';
  static const aramaEtkinlikler = 'Etkinlikler';
  static const aramaGorevler = 'Görevler';
  static const aramaBaslangic = 'Aramak için yazın';
  static const aramaTekrarli = 'tekrarlı';

  // --- hatırlatıcı izinleri
  static const hatirlaticiBolumu = 'Hatırlatıcılar';
  static const izinBildirim = 'Bildirim izni';
  static const izinTamZamanli = 'Tam zamanlı alarm';
  static const izinAcik = 'Açık';
  static const izinKapali = 'Kapalı';
  static const izinVer = 'İzin ver';
  static const bildirimKapaliUyari =
      'Bildirim izni kapalı: hatırlatıcılar görünmez. Etkinlik bildirimlerini açmak için izin verin ya da Android ayarlarından Takvim bildirimlerini açın.';
  static const tamZamanliUyari =
      'Tam zamanlı alarm izni yok: hatırlatıcılar yaklaşık zamanda (birkaç dakika sapmayla) gelir.';
  static String planliBildirim(int n) => n == 0 ? 'Planlı hatırlatıcı yok' : 'Planlı hatırlatıcı: $n';
  static String bildirimHatasi(Object e) => 'Hatırlatıcılar kurulamadı: $e';
  static const bildirimKanal = 'Hatırlatıcılar';
  static const bildirimKanalAciklama = 'Etkinlik hatırlatıcıları';
  static String bildirimGovde(int dk, String saat) =>
      dk == 0 ? 'Şimdi başlıyor · $saat' : '${hatirlaticiMetni(dk).replaceAll(' önce', '')} sonra · $saat';
  static const bildirimGovdeTumGun = 'Tüm gün';

  // --- senkron
  static const senkronBolumu = 'Masaüstüyle senkron';
  static const senkronGonder = 'Senkron dosyası gönder';
  static const senkronGonderAciklama = 'Tüm verinizi .takvimsync dosyası olarak paylaşın';
  static const senkronAc = 'Senkron dosyası aç';
  static const senkronAcAciklama = 'Masaüstünden gelen .takvimsync dosyasını seçin';
  static const senkronYardim =
      'Dosya WhatsApp/Drive/e-posta ile ya da kabloyla taşınır; Wi-Fi ile eşleştirme ise aynı ağdaki '
      'bilgisayarla doğrudan konuşur. İki yönlü çalışır: masaüstünden gelen dosyayı açın, sonra buradan da dosya gönderin.';
  static String sonSenkron(String? zaman) => zaman == null ? 'Henüz senkron yapılmadı' : 'Son senkron: $zaman';
  static const onizlemeBaslik = 'Senkron önizleme';
  static const onizlemeUygula = 'İçe aktar';
  static const onizlemeDegisiklikYok = 'Bu dosyada yeni bir değişiklik yok; veriniz zaten güncel.';
  static String onizlemeOzet(int etkinlik, int gorev, int silme) =>
      '$etkinlik etkinlik, $gorev görev, $silme silme; mevcut veriyle birleşecek.';
  static const onizlemeBirlesme = 'Veriler silinmez, yalnızca daha yeni kayıtlar uygulanır.';
  static const sonucBaslik = 'Senkron tamamlandı';
  static String sonucOzet(int eklenen, int guncellenen, int silinen, int atlanan) =>
      'Eklenen: $eklenen\nGüncellenen: $guncellenen\nSilinen: $silinen\nAtlanan: $atlanan';
  static const dosyaOkunamadi = 'Dosya okunamadı';
  static const dosyaTakvimSyncDegil = 'Bu bir Takvim senkron dosyası değil ya da bozuk. Veriniz değişmedi.';
  static String dosyaBozuk(String ayrinti) => 'Dosya geçersiz: $ayrinti. Veriniz değişmedi.';
  static String surumBuyuk(int s) =>
      'Bu dosya daha yeni bir Takvim sürümüyle oluşturulmuş (sürüm $s). Uygulamayı güncelleyin. Veriniz değişmedi.';
  static const dosyaGonderiliyor = 'Dosya hazırlanıyor…';
  static String gonderHatasi(Object e) => 'Dosya gönderilemedi: $e';
  static const dosyaAdiOnek = 'takvim';

  // --- Wi-Fi eşleştirme
  static const wifiEslestir = 'Wi-Fi ile eşleştir';
  static const wifiEslestirAciklama = 'Aynı Wi-Fi ağındaki bilgisayarla doğrudan senkron';
  static const wifiSayfaBaslik = 'Wi-Fi ile eşleştir';
  static const wifiAdimlar =
      '1. Telefon ve bilgisayar aynı Wi-Fi ağında olsun (misafir ağlar cihazları birbirinden ayırabilir).\n'
      '2. Bilgisayarda Takvim > Ayarlar > Telefonla senkron > "Wi-Fi ile eşleştir"e bas; ekranda QR kod çıkar.\n'
      '3. Telefonun kamera uygulamasıyla QR kodu okut ve açılan bağlantıyı Takvim ile aç. '
      'Açılamazsa bilgisayardaki bağlantı metnini kopyalayıp aşağıya yapıştır.\n'
      '4. Önce bağlantıyı onaylarsın, sonra neyin birleşeceğini görüp bir kez daha onaylarsın. Onaylamazsan hiçbir veri gönderilmez.';
  static const wifiBaglantiAlan = 'Bağlantıyı yapıştır';
  static const wifiBaglantiIpucu = 'https://aktenak.tech/s#...';
  static const wifiDevam = 'Devam';
  static const wifiYedekYol = 'Wi-Fi çalışmazsa "Senkron dosyası gönder / aç" ile dosya aktararak da senkron yapabilirsin.';
  static const wifiMesgul = 'Bir Wi-Fi eşleştirme işlemi zaten sürüyor.';
  static const wifiBaglantiGecersizBaslik = 'Bağlantı geçersiz';
  static String wifiBaglantiHata(WifiBaglantiHataTuru t) => switch (t) {
        WifiBaglantiHataTuru.bicimsiz =>
          'Bu, bilgisayarın eşleştirme ekranındaki bir Takvim bağlantısı değil ya da bozuk. Hiçbir yere bağlanılmadı. '
              'Bağlantıyı bilgisayardaki eşleştirme ekranından kopyala.',
        WifiBaglantiHataTuru.surumYeni =>
          "Bu bağlantı Takvim'in daha yeni bir sürümüyle oluşturulmuş. Hem telefondaki hem bilgisayardaki Takvim'i güncelle.",
        WifiBaglantiHataTuru.ozelOlmayanAdres =>
          'Bağlantıdaki adres yerel bir ağ adresi değil, bu yüzden bağlanılmadı. '
              'Gerçek eşleştirme bağlantıları her zaman aynı Wi-Fi ağındaki bir adresi gösterir; bağlantıyı başka biri gönderdiyse güvenme.',
      };
  /// Görünmez karakterden oluşan ad ayrıştırıcıda boşa iner; burada "Bilinmeyen cihaz" gösterilir.
  static String wifiCihaz(String ad, String adres) => '${ad.isEmpty ? 'Bilinmeyen cihaz' : '«$ad»'} ($adres)';
  static const wifiOnayBaslik = 'Bu bilgisayarla eşleşilsin mi?';
  static String wifiOnayMetni(String ad, String adres) =>
      '${wifiCihaz(ad, adres)} ile eşleşilecek.\n\n'
      'Bunu, bilgisayarında senin açtığın eşleştirme ekranından aldıysan devam et. '
      'Bir mesajla ya da başkasından geldiyse devam etme.';
  static const wifiBaglan = 'Bağlan';
  static const wifiBaglaniyor = 'Bilgisayara bağlanılıyor…';
  static const wifiOnayBekleniyor = 'Bilgisayarın onayı bekleniyor… Bilgisayardaki onay penceresine bak (en çok 1,5 dakika).';
  static const wifiOnizlemeBaslik = 'Bilgisayardan gelen değişiklikler';
  static String wifiOnizlemeNot(String ad, String adres) =>
      'Karşı cihaz: ${wifiCihaz(ad, adres)}.\n'
      'Onaylarsan bu değişiklikler telefonuna işlenir, ardından telefonun tam durumu bu cihaza gönderilir '
      '(bilgisayar da ayrıca onay ister). Vazgeçersen hiçbir veri gönderilmez.';
  static const wifiBirlestirGonder = 'Birleştir ve gönder';
  static const wifiDosyaGecersiz = 'Bilgisayardan gelen veri okunamadı';
  static const wifiSonucBaslik = 'Wi-Fi senkronu tamamlandı';
  static String wifiSonucOzet(ImportRaporu telefon, WifiRapor bilgisayar) =>
      'Telefona\n${sonucOzet(telefon.added, telefon.updated, telefon.deleted, telefon.skipped)}\n\n'
      'Bilgisayara\n${sonucOzet(bilgisayar.added, bilgisayar.updated, bilgisayar.deleted, bilgisayar.skipped)}';
  static const wifiHataBaslik = 'Wi-Fi eşleştirme tamamlanamadı';
  static const wifiGuvenlikBaslik = 'Güvenlik uyarısı';
  static const wifiGonderilemediEk =
      '\n\nTelefondaki birleştirme yapıldı; bilgisayara veri eklenmedi. İstersen yeniden eşleştirebilir ya da dosya aktarabilirsin.';
  static const wifiGonderIptalEk =
      'Telefondaki birleştirme yapıldı; bağlantı kesildi. Bilgisayarda onay penceresi açıldıysa "Hayır" de.';
  static String wifiHata(WifiHataTuru t, [String ayrinti = '']) {
    final ek = ayrinti.isEmpty ? '' : ' ($ayrinti)';
    return switch (t) {
      WifiHataTuru.ozelOlmayanAdres => 'Adres yerel bir ağ adresi değil; bağlanılmadı.',
      WifiHataTuru.ulasilamadi =>
        'Bilgisayara ulaşılamadı. Telefon ve bilgisayar aynı Wi-Fi ağında mı? Misafir ağlar cihazları birbirinden ayırabilir; '
            'o durumda dosya aktararak senkron yap. Bilgisayardaki eşleştirme ekranı da açık olmalı.$ek',
      WifiHataTuru.sureDoldu =>
        'Bilgisayar zamanında yanıt vermedi (süre doldu). Eşleştirme ekranı kapanmış olabilir; bilgisayarda yeniden başlat.',
      WifiHataTuru.tlsKurulamadi => 'Güvenli bağlantı kurulamadı. Bu adres bir Takvim eşleştirme oturumu olmayabilir.',
      WifiHataTuru.parmakIzi =>
        'Bağlandığın cihazın kimliği QR koddakiyle uyuşmuyor, bağlantı kesildi ve hiçbir veri gönderilmedi. '
            'Bağlantıyı yalnız kendi bilgisayarındaki eşleştirme ekranından al. Aldıysan ve bu uyarı sürüyorsa ağdaki başka bir cihaz araya girmeye çalışıyor olabilir.',
      WifiHataTuru.yetkisiz =>
        'Bilgisayar bağlantı kodunu kabul etmedi. Eşleştirme ekranı yenilenmiş ya da kapanmış olabilir; yeni QR kodla yeniden dene.',
      WifiHataTuru.reddedildi => 'Bilgisayar gönderilen veriyi reddetti (onay penceresinde "Hayır" denmiş olabilir).',
      WifiHataTuru.masaustuSuresiDoldu =>
        'Bilgisayarda onay süresi doldu. Yeniden eşleştirip bilgisayardaki onay penceresine zamanında bak.',
      WifiHataTuru.surum => 'Telefon ve bilgisayardaki Takvim farklı sürüm bekliyor. İkisini de güncelle.$ek',
      WifiHataTuru.gecersizDosya => 'Bilgisayar gönderilen veriyi geçersiz buldu$ek.',
      WifiHataTuru.cokBuyuk => 'Veri çok büyük (en çok 16 MB).$ek',
      WifiHataTuru.beklenmeyen => 'Bilgisayardan beklenmeyen bir yanıt geldi$ek.',
      WifiHataTuru.iptal => 'İptal edildi.',
    };
  }

  // --- hakkında
  static const hakkindaBolumu = 'Hakkında';
  static const gorunumBolumu = 'Görünüm';
  static const temaSistem = 'Sistem';
  static const temaKoyu = 'Koyu';
  static const temaAcik = 'Açık';
  static String surum(String s) => 'Sürüm $s';
  static const verilerYalnizTelefonda =
      'Veriler yalnız bu telefonda tutulur, hesap gerekmez. Uygulama yalnız sen "Wi-Fi ile eşleştir"i kullanınca '
      'aynı ağdaki bilgisayarına bağlanır; başka hiçbir yere bağlanmaz.';
  static const lisans = 'Lisans: MIT';
  static const lisansMetni = 'MIT License\n\nCopyright (c) 2026 Arda\n\n'
      'Permission is hereby granted, free of charge, to any person obtaining a copy of this software and '
      'associated documentation files (the "Software"), to deal in the Software without restriction, '
      'including without limitation the rights to use, copy, modify, merge, publish, distribute, '
      'sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is '
      'furnished to do so, subject to the following conditions:\n\n'
      'The above copyright notice and this permission notice shall be included in all copies or '
      'substantial portions of the Software.\n\n'
      'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT '
      'NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND '
      'NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, '
      'DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, '
      'OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.';

  // --- açılış hataları
  static const acilisHataBaslik = 'Veri açılamadı';
  static String acilisHata(Object e) =>
      'Takvim verisi okunamadı. Hiçbir şey silinmedi ve üzerine yazılmadı.\n\n$e';
  static const acilisSurumHata = 'Veri dosyası bu uygulamadan daha yeni bir sürümle yazılmış. Uygulamayı güncelleyin.';
}
