param([string]$BundleDirectory)
$ErrorActionPreference = 'Stop'
$releaseProject = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$releaseBundle = if ($BundleDirectory) {
    (Resolve-Path -LiteralPath $BundleDirectory).Path
} else {
    Join-Path $releaseProject 'build/windows/x64/runner/Release'
}
if (!(Test-Path -LiteralPath (Join-Path $releaseBundle 'ledgy_2_0.exe'))) {
    throw 'Jalankan flutter build windows --release --no-tree-shake-icons lebih dahulu.'
}
$releasePrivateFiles = Get-ChildItem -LiteralPath $releaseBundle -File -Recurse |
    Where-Object { $_.Name -match '(?i)(\.sqlite(?:-wal|-shm)?$|\.db(?:-wal|-shm)?$|\.jks$|\.keystore$|^key\.properties$|^client-config\.local\.json$)' }
if ($releasePrivateFiles) { throw 'Ada file database/kredensial di bundle. Pindahkan ke lokasi privat sebelum packaging.' }
$releaseVersionLine = Get-Content (Join-Path $releaseProject 'pubspec.yaml') |
    Where-Object { $_ -match '^version: ' } | Select-Object -First 1
$releaseVersion = ($releaseVersionLine -replace '^version:\s*', '').Trim()
if ($releaseVersion -notmatch '^\d+\.\d+\.\d+\+\d+$') { throw 'Versi pubspec tidak valid.' }
$releaseNativeVersion = (Get-Item -LiteralPath (Join-Path $releaseBundle 'ledgy_2_0.exe')).VersionInfo.ProductVersion.Trim()
if ($releaseNativeVersion -ne $releaseVersion) { throw 'Versi bundle berbeda dari pubspec. Pilih build terbaru.' }
$releaseOutput = Join-Path $releaseProject 'build/releases'
New-Item -ItemType Directory -Path $releaseOutput -Force | Out-Null
$releaseArchive = Join-Path $releaseOutput "ledgy-2.0-windows-$releaseVersion-x64.zip"
if (Test-Path -LiteralPath $releaseArchive) {
    throw 'Arsip versi ini sudah ada. Naikkan versi/build number atau simpan arsip lama sebelum membuat ulang.'
}
Compress-Archive -Path (Join-Path $releaseBundle '*') -DestinationPath $releaseArchive -CompressionLevel Optimal
Get-Item -LiteralPath $releaseArchive | Select-Object FullName, Length
Get-FileHash -LiteralPath $releaseArchive -Algorithm SHA256 | Select-Object Algorithm, Hash
