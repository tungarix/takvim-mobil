# Masaustu <-> mobil senkron UCTAN UCA dogrulamasi: tek komut.
#
#   powershell -File tool/e2e/calistir.ps1                 # her sey
#   powershell -File tool/e2e/calistir.ps1 -Senaryo a,b    # secili senaryolar (a,b,c,d,e,olcek,f)
#
# Adimlar: (1) mobil saf Dart regresyon denetimleri, (2) iki cihazin cift yonlu e2e senaryolari.
# Masaustu kodu GECICI SQLite'la, mobil kodu GECICI JSON'la surulur; gercek veriye dokunulmaz.
# flutter test KULLANILMAZ (bu makinede motor cokuyor): yalniz `dart run` ve masaustu venv'i.
# Masaustu deposu varsayilan olarak ..\takvim; baska yerdeyse $env:TAKVIM_YOLU ile verin.
param(
    [string]$Senaryo = 'a,b,c,d,e,olcek,f',
    [switch]$Tut
)

$ErrorActionPreference = 'Stop'
$kok = (Resolve-Path "$PSScriptRoot\..\..").Path
$takvim = if ($env:TAKVIM_YOLU) { $env:TAKVIM_YOLU } else { (Resolve-Path "$kok\..\takvim").Path }
$python = Join-Path $takvim '.venv\Scripts\python.exe'
if (-not (Test-Path $python)) { throw "Masaustu venv'i yok: $python (TAKVIM_YOLU dogru mu?)" }
if (-not (Get-Command dart -ErrorAction SilentlyContinue)) { throw 'dart PATH icinde degil' }
$env:TAKVIM_YOLU = $takvim
$env:PYTHONIOENCODING = 'utf-8'

Push-Location $kok
try {
    Write-Host '== 1/2 mobil regresyon denetimleri (dart run) =='
    dart run tool/e2e/mobil_regresyon.dart
    if ($LASTEXITCODE -ne 0) { throw 'mobil regresyon denetimleri basarisiz' }

    Write-Host "`n== 2/2 masaustu <-> mobil e2e ($Senaryo) =="
    $args2 = @('tool/e2e/e2e.py', '--senaryo', $Senaryo)
    if ($Tut) { $args2 += '--tut' }
    & $python @args2
    if ($LASTEXITCODE -ne 0) { throw 'e2e senaryolari basarisiz' }
    Write-Host "`nTUM E2E DENETIMLERI GECTI."
} finally {
    Pop-Location
}
