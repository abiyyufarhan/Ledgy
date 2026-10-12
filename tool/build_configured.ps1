param(
    [ValidateSet('windows', 'android', 'android-debug', 'all')]
    [string]$Target = 'windows',
    [string]$FlutterPath = 'D:\flutter-sdk\bin\flutter.bat'
)
$ErrorActionPreference = 'Stop'
$configuredProject = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$configuredFile = Join-Path $configuredProject 'supabase/client-config.local.json'
if (!(Test-Path -LiteralPath $configuredFile)) {
    throw 'Konfigurasi cloud lokal belum tersedia; build dihentikan.'
}
$configuredCloud = Get-Content -LiteralPath $configuredFile -Raw | ConvertFrom-Json
$configuredUrl = $null
if (![Uri]::TryCreate([string]$configuredCloud.SUPABASE_URL, [UriKind]::Absolute, [ref]$configuredUrl) -or
    $configuredUrl.Scheme -ne 'https' -or $configuredUrl.Host.Contains('YOUR_PROJECT_REF')) {
    throw 'Project URL cloud belum valid.'
}
$configuredKey = [string]$configuredCloud.SUPABASE_ANON_KEY
if (!$configuredKey.StartsWith('sb_publishable_')) {
    try {
        $configuredParts = $configuredKey.Split('.')
        if ($configuredParts.Length -ne 3) { throw 'invalid' }
        $configuredPayload = $configuredParts[1].Replace('-', '+').Replace('_', '/')
        $configuredPayload = $configuredPayload.PadRight($configuredPayload.Length + ((4 - $configuredPayload.Length % 4) % 4), '=')
        $configuredClaims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($configuredPayload)) | ConvertFrom-Json
        if ($configuredClaims.role -ne 'anon') { throw 'invalid' }
    } catch { throw 'Gunakan key publik publishable atau anon untuk klien.' }
}
if ($configuredCloud.SUPABASE_AUTH_REDIRECT_URL -and
    $configuredCloud.SUPABASE_AUTH_REDIRECT_URL -ne 'com.ledgy.ledgy2://auth/callback') {
    throw 'Callback konfigurasi harus memakai identitas Ledgy 2.0.'
}
Push-Location -LiteralPath $configuredProject
try {
    $configuredCommon = @('--dart-define-from-file=supabase/client-config.local.json')
    if ($Target -in @('windows', 'all')) {
        & $FlutterPath --no-version-check build windows --release --no-tree-shake-icons @configuredCommon
        if ($LASTEXITCODE -ne 0) { throw 'Build Windows gagal.' }
    }
    if ($Target -in @('android', 'all')) {
        & $FlutterPath --no-version-check build apk --release --no-tree-shake-icons @configuredCommon
        if ($LASTEXITCODE -ne 0) { throw 'Build Android gagal.' }
    }
    if ($Target -eq 'android-debug') {
        & $FlutterPath --no-version-check build apk --debug @configuredCommon
        if ($LASTEXITCODE -ne 0) { throw 'Build Android debug gagal.' }
    }
} finally { Pop-Location }
