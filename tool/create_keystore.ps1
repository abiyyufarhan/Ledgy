param([Parameter(Mandatory = $true)][string]$Keytool)
$ErrorActionPreference = 'Stop'
if ($env:OS -eq 'Windows_NT') {
    $releaseIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    if ($releaseIdentity -match 'CodexSandbox') {
        throw 'Jalankan generator sebagai pengguna Windows pemilik proyek, bukan akun sandbox.'
    }
}
$releaseProject = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$releasePrivate = Join-Path $releaseProject 'release-private'
$releaseStore = Join-Path $releasePrivate 'ledgy-upload.jks'
$releaseProperties = Join-Path $releaseProject 'android/key.properties'
if ((Test-Path -LiteralPath $releaseStore) -or (Test-Path -LiteralPath $releaseProperties)) {
    throw 'Signing sudah ada atau belum lengkap. Tidak ada file yang ditimpa. Gunakan keystore yang sudah ada.'
}
if (!(Test-Path -LiteralPath $Keytool)) { throw 'keytool.exe tidak ditemukan.' }
New-Item -ItemType Directory -Path $releasePrivate -Force | Out-Null
$releaseBytes = New-Object byte[] 36
$releaseRandom = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$releaseRandom.GetBytes($releaseBytes)
$releaseRandom.Dispose()
$releasePassword = [Convert]::ToBase64String($releaseBytes)
try {
    # Environment inputs keep the password out of process arguments and output.
    $env:LEDGY_GENERATED_PASSWORD = $releasePassword
    & $Keytool -genkeypair -noprompt -storetype JKS -keyalg RSA -keysize 4096 `
        -validity 10000 -alias ledgy-upload -keystore $releaseStore `
        -storepass:env LEDGY_GENERATED_PASSWORD -keypass:env LEDGY_GENERATED_PASSWORD `
        -dname 'CN=Ledgy Release, OU=Ledgy, O=Ledgy, C=ID'
    if ($LASTEXITCODE -ne 0) { throw 'Pembuatan keystore gagal; periksa file parsial sebelum mencoba lagi.' }
    # Generated private build configuration, not checked-in source.
    $releaseText = "storeFile=../release-private/ledgy-upload.jks`nkeyAlias=ledgy-upload`nstorePassword=$releasePassword`nkeyPassword=$releasePassword`n"
    [System.IO.File]::WriteAllText($releaseProperties, $releaseText, [System.Text.UTF8Encoding]::new($false))
    if ($env:OS -eq 'Windows_NT') {
        & icacls $releaseStore /inheritance:r /grant:r "${releaseIdentity}:F" '*S-1-5-18:F' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Gagal membatasi izin keystore.' }
        & icacls $releaseProperties /inheritance:r /grant:r "${releaseIdentity}:F" '*S-1-5-18:F' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Gagal membatasi izin kredensial.' }
    }
    Write-Output 'Keystore dan android/key.properties berhasil dibuat. Backup keduanya ke penyimpanan terenkripsi; password tidak dicetak.'
} finally {
    Remove-Item Env:LEDGY_GENERATED_PASSWORD -ErrorAction SilentlyContinue
    $releasePassword = $null
    $releaseText = $null
    [Array]::Clear($releaseBytes, 0, $releaseBytes.Length)
}
