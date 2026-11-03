# Testleri dosya dosya (her biri ayrı flutter_tester süreci) çalıştırır.
#
# Neden: bu Windows makinesinde flutter_tester motoru rastgele 0xC0000005 (erişim ihlali)
# ile çöküyor (bkz. README "Bilinen sınırlar"). Çökme testin hatası DEĞİL: süreç ölünce kalan
# testler mesajsız "did not complete" olur. Böyle bir çökme olursa YALNIZ o dosya yeniden denenir;
# gerçek bir test hatası (beklenti/istisna metni) ASLA yeniden denenmez ve betik hata ile çıkar.
param([int]$Deneme = 8)

$dosyalar = Get-ChildItem -Path "$PSScriptRoot\..\test" -Filter '*_test.dart' | Sort-Object Name
$basarisiz = @()
foreach ($d in $dosyalar) {
    $tamam = $false
    for ($i = 1; $i -le $Deneme -and -not $tamam; $i++) {
        $cikti = flutter test "test/$($d.Name)" 2>&1 | Out-String
        if ($cikti -match 'All tests passed!') {
            $tamam = $true
            $not = if ($i -gt 1) { " (motor çökmesi nedeniyle $i. denemede)" } else { '' }
            Write-Host ("OK   {0}{1}" -f $d.Name, $not)
        } else {
            # Çökme imzası: yalnızca "did not complete" / yüklenemedi, başka hata metni yok.
            $cokme = ($cikti -match 'did not complete|Connection closed before test suite loaded') -and
                     -not ($cikti -match 'EXCEPTION CAUGHT|Expected:|Actual:|TestFailure|Bad state')
            if (-not $cokme) { Write-Host $cikti; break }
        }
    }
    if (-not $tamam) { Write-Host "FAIL $($d.Name)"; $basarisiz += $d.Name }
}
if ($basarisiz.Count -gt 0) { Write-Host "BASARISIZ: $($basarisiz -join ', ')"; exit 1 }
Write-Host 'Tüm test dosyaları geçti.'
