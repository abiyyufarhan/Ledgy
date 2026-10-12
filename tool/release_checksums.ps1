$ErrorActionPreference = 'Stop'
$releaseProject = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$releaseVersionLine = Get-Content (Join-Path $releaseProject 'pubspec.yaml') |
    Where-Object { $_ -match '^version: ' } | Select-Object -First 1
$releaseVersion = ($releaseVersionLine -replace '^version:\s*', '').Trim()
if ($releaseVersion -notmatch '^\d+\.\d+\.\d+\+\d+$') { throw 'Versi pubspec tidak valid.' }
$releaseFiles = @(
    'build/app/outputs/flutter-apk/app-release.apk',
    "build/releases/ledgy-2.0-windows-$releaseVersion-x64.zip"
)
$releaseVersionParts = $releaseVersion.Split('+')
$releaseOptionalFiles = @(
    'build/app/outputs/bundle/release/app-release.aab',
    'build/app/outputs/flutter-apk/app-debug.apk',
    "build/releases/Ledgy-2.0-Setup-$($releaseVersionParts[0])-build$($releaseVersionParts[1])-x64.exe"
)
$releaseFiles += $releaseOptionalFiles | Where-Object {
    Test-Path -LiteralPath (Join-Path $releaseProject $_)
}
$releaseLines = foreach ($releaseFile in $releaseFiles) {
    $releaseHash = Get-FileHash -LiteralPath (Join-Path $releaseProject $releaseFile) -Algorithm SHA256
    "$($releaseHash.Hash.ToLowerInvariant())  $releaseFile"
}
$releaseOutput = Join-Path $releaseProject 'build/releases/SHA256SUMS.txt'
[IO.File]::WriteAllLines($releaseOutput, $releaseLines, [Text.UTF8Encoding]::new($false))
Write-Output "Hash $($releaseFiles.Count) paket tersedia disimpan di build/releases/SHA256SUMS.txt."
