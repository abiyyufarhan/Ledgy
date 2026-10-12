param(
    [string]$CompilerPath,
    [string]$RuntimeDirectory,
    [string]$BundleDirectory
)
$ErrorActionPreference = 'Stop'
$installerProject = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$installerBundle = if ($BundleDirectory) {
    (Resolve-Path -LiteralPath $BundleDirectory).Path
} else {
    Join-Path $installerProject 'build/windows/x64/runner/Release'
}
$installerRequired = @('ledgy_2_0.exe', 'flutter_windows.dll', 'sqlite3.dll', 'data/app.so', 'data/flutter_assets/NativeAssetsManifest.json')
foreach ($installerRequiredFile in $installerRequired) {
    if (!(Test-Path -LiteralPath (Join-Path $installerBundle $installerRequiredFile))) {
        throw "Bundle tidak lengkap: $installerRequiredFile. Build Windows release lebih dahulu."
    }
}
$installerPrivateFiles = Get-ChildItem -LiteralPath $installerBundle -File -Recurse |
    Where-Object { $_.Name -match '(?i)(\.(sqlite(?:-wal|-shm)?|db(?:-wal|-shm)?|jks|keystore|pfx|p12|pem)$|^key\.properties$|^client-config\.local\.json$|^\.env)' }
if ($installerPrivateFiles) { throw 'Bundle mengandung data pribadi atau kredensial; installer tidak dibuat.' }
$installerVersionLine = Get-Content -LiteralPath (Join-Path $installerProject 'pubspec.yaml') |
    Where-Object { $_ -match '^version: ' } | Select-Object -First 1
if ($installerVersionLine -notmatch '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') { throw 'Versi pubspec tidak valid.' }
$installerVersion = $Matches[1]
$installerBuild = $Matches[2]
$installerNativeVersion = (Get-Item -LiteralPath (Join-Path $installerBundle 'ledgy_2_0.exe')).VersionInfo.ProductVersion.Trim()
if ($installerNativeVersion -ne "$installerVersion+$installerBuild") {
    throw 'Versi bundle berbeda dari pubspec. Pilih build terbaru; installer tidak dibuat.'
}
$installerOutputName = "Ledgy-2.0-Setup-$installerVersion-build$installerBuild-x64"
$installerOutputDir = Join-Path $installerProject 'build/releases'
$installerOutputFile = Join-Path $installerOutputDir "$installerOutputName.exe"
if (Test-Path -LiteralPath $installerOutputFile) { throw 'Installer versi ini sudah ada. Naikkan versi/build sebelum membuat rilis baru.' }

if (!$CompilerPath) {
    $installerCompilers = @(
        (Join-Path $installerProject 'build/installer-tools/InnoSetup/ISCC.exe'),
        "${env:ProgramFiles(x86)}\Inno Setup 7\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 7\ISCC.exe"
    )
    $CompilerPath = $installerCompilers | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (!$CompilerPath -or !(Test-Path -LiteralPath $CompilerPath)) { throw 'Compiler Inno Setup belum tersedia; isi -CompilerPath.' }
if (!$RuntimeDirectory) {
    $installerVsRoots = @("$env:ProgramFiles\Microsoft Visual Studio", "${env:ProgramFiles(x86)}\Microsoft Visual Studio")
    $installerRuntimeCandidates = foreach ($installerVsRoot in $installerVsRoots) {
        if (Test-Path -LiteralPath $installerVsRoot) {
            Get-ChildItem -LiteralPath $installerVsRoot -Directory -Recurse -Filter 'Microsoft.VC*.CRT' |
                Where-Object { $_.Parent.Name -eq 'x64' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'vcruntime140.dll')) }
        }
    }
    $RuntimeDirectory = $installerRuntimeCandidates | Sort-Object {
        [version][regex]::Match((Get-Item -LiteralPath (Join-Path $_.FullName 'vcruntime140.dll')).VersionInfo.FileVersion, '^\d+\.\d+\.\d+\.\d+').Value
    } -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (!$RuntimeDirectory) { throw 'Runtime Visual C++ x64 belum tersedia; isi -RuntimeDirectory dari folder redistributable Visual Studio.' }
$installerRuntimeFiles = @(Get-ChildItem -LiteralPath $RuntimeDirectory -Filter '*.dll' -File)
foreach ($installerRuntimeFile in $installerRuntimeFiles) {
    if ((Get-AuthenticodeSignature -LiteralPath $installerRuntimeFile.FullName).Status -ne 'Valid') {
        throw 'Tanda tangan runtime Visual C++ tidak valid.'
    }
}
foreach ($installerRuntimeRequired in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    if (!(Test-Path -LiteralPath (Join-Path $RuntimeDirectory $installerRuntimeRequired))) { throw "Runtime tidak lengkap: $installerRuntimeRequired" }
}

$installerStage = Join-Path $installerProject ('build/installer-staging/' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $installerStage -Force | Out-Null
foreach ($installerBundleEntry in Get-ChildItem -LiteralPath $installerBundle) {
    # This root manifest is a build diagnostic with developer paths. The portable
    # runtime manifest is already inside data/flutter_assets.
    if ($installerBundleEntry.Name -eq 'native_assets.json' -or $installerBundleEntry.Extension -eq '.pdb') { continue }
    Copy-Item -LiteralPath $installerBundleEntry.FullName -Destination $installerStage -Recurse
}
foreach ($installerRuntimeFile in $installerRuntimeFiles) {
    Copy-Item -LiteralPath $installerRuntimeFile.FullName -Destination $installerStage
}
$installerAssets = Get-Content -LiteralPath (Join-Path $installerStage 'data/flutter_assets/NativeAssetsManifest.json') -Raw | ConvertFrom-Json
foreach ($installerAsset in $installerAssets.'native-assets'.windows_x64.PSObject.Properties) {
    $installerAssetName = [string]$installerAsset.Value[1]
    if ([IO.Path]::IsPathRooted($installerAssetName) -or !(Test-Path -LiteralPath (Join-Path $installerStage $installerAssetName))) {
        throw 'Native asset memakai lokasi mesin pengembang atau tidak tersedia dalam installer.'
    }
}
& node (Join-Path $PSScriptRoot 'verify_windows_icons.mjs') $installerStage
if ($LASTEXITCODE -ne 0) { throw 'Pemeriksaan font ikon gagal.' }
& node (Join-Path $PSScriptRoot 'verify_windows_dependencies.mjs') $installerStage
if ($LASTEXITCODE -ne 0) { throw 'Pemeriksaan dependency Windows gagal.' }
New-Item -ItemType Directory -Path $installerOutputDir -Force | Out-Null
& $CompilerPath "/DStageDir=$installerStage" "/DAppVersion=$installerVersion+$installerBuild" "/DFileVersion=$installerVersion.$installerBuild" "/DOutputDir=$installerOutputDir" "/DOutputName=$installerOutputName" (Join-Path $PSScriptRoot 'installer/ledgy.iss')
if ($LASTEXITCODE -ne 0) { throw 'Kompilasi installer gagal.' }
$installerHash = (Get-FileHash -LiteralPath $installerOutputFile -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$installerOutputFile.sha256", "$installerHash  $installerOutputName.exe`n", [Text.UTF8Encoding]::new($false))
Get-Item -LiteralPath $installerOutputFile | Select-Object FullName,Length
Write-Output "SHA256: $installerHash"
