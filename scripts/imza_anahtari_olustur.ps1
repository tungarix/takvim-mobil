# Takvim (Android) sürüm imza anahtarını BİR KEZ oluşturur ve GitHub secret'larına yükler.
#
# - Anahtar ve şifresi depo DIŞINA yazılır (varsayılan: Belgeler\takvim-mobil-imza).
#   O klasörü USB'ye / Drive'a yedekle: anahtar kaybolursa sonraki sürümler eskisinin
#   üstüne kurulamaz (ilk sürümden itibaren hep aynı anahtar kullanılmalı).
# - Şifre rastgele üretilir, ekrana basılmaz; secret'lara stdin'den gider.
# - Ekrana yalnız sertifikanın SHA-256 parmak izi basılır (gizli değil).
#
# Kullanım (depo kökünde, gh oturumu açıkken):
#   powershell -ExecutionPolicy Bypass -File scripts\imza_anahtari_olustur.ps1

param(
    [string]$Klasor = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'takvim-mobil-imza'),
    [string]$Repo = 'tungarix/takvim-mobil'
)
$ErrorActionPreference = 'Stop'

$anahtar = Join-Path $Klasor 'takvim-surum.jks'
$sifreDosyasi = Join-Path $Klasor 'sifre.txt'
if ((Test-Path $anahtar) -and -not (Test-Path $sifreDosyasi)) {
    # Yarım kalmış önceki deneme: şifresi kaydedilmemiş anahtar kullanılamaz.
    # Silinmez, kenara alınır.
    $kenar = "$anahtar.yarim-$(Get-Date -Format yyyyMMddHHmmss)"
    Move-Item $anahtar $kenar
    Write-Host "Şifresiz yarım anahtar kenara alındı: $kenar"
}
if (Test-Path $anahtar) {
    throw "Anahtar zaten var: $anahtar. Üzerine yazılmaz; yeni anahtar eski APK'larla uyumsuz olur."
}

$keytool = (Get-Command keytool -ErrorAction SilentlyContinue).Source
if (-not $keytool) {
    # PATH'teki java çoğu zaman Oracle'ın javapath kısayolu; keytool JDK'nın bin'inde.
    $keytool = Get-ChildItem 'C:\Program Files\Java', 'C:\Program Files\Eclipse Adoptium' `
        -Recurse -Depth 3 -Filter keytool.exe -ErrorAction SilentlyContinue |
        Select-Object -Last 1 -ExpandProperty FullName
}
if (-not $keytool -or -not (Test-Path $keytool)) { throw 'keytool bulunamadı (Java ile gelir).' }

New-Item -ItemType Directory -Force $Klasor | Out-Null

# 32 karakter rastgele şifre (harf + rakam; keytool argümanında kaçış gerektirmez).
$harfler = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
$bayt = New-Object byte[] 32
$rng.GetBytes($bayt)
$sifre = -join ($bayt | ForEach-Object { $harfler[$_ % $harfler.Length] })

# keytool ve gh bilgi satırlarını stderr'e yazar; Windows PowerShell 5.1 bunu Stop
# altında hata sayıp betiği keserdi. Buradan sonra yalnız çıkış kodlarına bakılır.
$ErrorActionPreference = 'Continue'
& $keytool -genkeypair -keystore $anahtar -storetype PKCS12 -alias takvim `
    -keyalg RSA -keysize 4096 -validity 10000 `
    -storepass $sifre -keypass $sifre `
    -dname 'CN=Aktenak Takvim, O=Aktenak, C=TR' 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'keytool anahtarı oluşturamadı.' }

Set-Content -Path $sifreDosyasi -Value $sifre -Encoding ascii -NoNewline
@"
Takvim (Android) sürüm imza anahtarı ($(Get-Date -Format yyyy-MM-dd))
Alias: takvim. Şifre: sifre.txt (anahtar ve alias için aynı).
GitHub secret'ları: TAKVIM_KEYSTORE_BASE64, TAKVIM_KEYSTORE_PASSWORD ($Repo).
Bu klasörü yedekle. Kaybolursa sonraki APK'lar eskisinin üstüne kurulmaz.
"@ | Set-Content -Path (Join-Path $Klasor 'BENIOKU.txt') -Encoding utf8

# --body: PowerShell native programa pipe ederken sona satır sonu ekler, şifreyi bozardı.
gh secret set TAKVIM_KEYSTORE_BASE64 -R $Repo --body ([Convert]::ToBase64String([IO.File]::ReadAllBytes($anahtar)))
if ($LASTEXITCODE -ne 0) { throw 'Secret yüklenemedi (gh auth status?).' }
gh secret set TAKVIM_KEYSTORE_PASSWORD -R $Repo --body $sifre
if ($LASTEXITCODE -ne 0) { throw 'Secret yüklenemedi (gh auth status?).' }
$sifre = $null

Write-Host "Tamam. Anahtar: $Klasor"
Write-Host 'Sertifika parmak izi:'
& $keytool -list -v -keystore $anahtar -storepass (Get-Content (Join-Path $Klasor 'sifre.txt') -Raw) -alias takvim 2>$null |
    Select-String 'SHA256:'
Write-Host "Şimdi bu klasörü yedekle: $Klasor"
