param(
    [Parameter(Mandatory=$true)][string]$InstallerPath,
    [Parameter(Mandatory=$true)][string]$StageDirectory
)
$ErrorActionPreference = 'Stop'
$validationProject = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$validationInstaller = (Resolve-Path -LiteralPath $InstallerPath).Path
$validationStage = (Resolve-Path -LiteralPath $StageDirectory).Path
$validationRegistry = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{33D2267D-7D60-46FE-B3C7-7A48657F27AA}_is1'
$validationProtocol = 'HKCU:\Software\Classes\com.ledgy.ledgy2'
if ((Test-Path -LiteralPath $validationRegistry) -or (Test-Path -LiteralPath $validationProtocol)) {
    throw 'Ada instalasi/registrasi Ledgy pengguna. Uji harus dijalankan pada profil Windows bersih.'
}
$validationId = [guid]::NewGuid().ToString('N')
$validationRoot = Join-Path $validationProject "build/installer-validation/$validationId"
$validationApp = Join-Path $validationRoot 'Installed'
$validationGroup = 'Ledgy 2.0'
$validationGroupPath = Join-Path ([Environment]::GetFolderPath('StartMenu')) "Programs/$validationGroup"
if (Test-Path -LiteralPath $validationGroupPath) { throw 'Folder shortcut uji sudah ada.' }
New-Item -ItemType Directory -Path $validationRoot -Force | Out-Null
function Invoke-ValidationSetup([string]$Executable, [string[]]$Arguments) {
    $validationProcess = Start-Process -FilePath $Executable -ArgumentList $Arguments -WindowStyle Hidden -PassThru
    $validationProcess.WaitForExit()
    if ($validationProcess.ExitCode -ne 0) { throw "Installer/uninstaller gagal: $($validationProcess.ExitCode)" }
}
$validationBaseArguments = @('/VERYSILENT','/SUPPRESSMSGBOXES','/SP-','/NORESTART','/LANG=indonesian','/TASKS=""',('/DIR="' + $validationApp + '"'),('/GROUP="' + $validationGroup + '"'))
$validationUninstaller = Join-Path $validationApp 'unins000.exe'
try {
    Invoke-ValidationSetup $validationInstaller ($validationBaseArguments + ('/LOG="' + (Join-Path $validationRoot 'install.log') + '"'))
    $validationPayload = @(Get-ChildItem -LiteralPath $validationStage -File -Recurse)
    foreach ($validationFile in $validationPayload) {
        $validationRelative = $validationFile.FullName.Substring($validationStage.Length + 1)
        $validationTarget = Join-Path $validationApp $validationRelative
        if ((Get-FileHash -LiteralPath $validationFile.FullName).Hash -ne (Get-FileHash -LiteralPath $validationTarget).Hash) {
            throw "Isi installer berbeda: $validationRelative"
        }
    }
    $validationShortcutPath = Join-Path $validationGroupPath 'Ledgy 2.0.lnk'
    $validationShortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($validationShortcutPath)
    if ($validationShortcut.TargetPath -ne (Join-Path $validationApp 'ledgy_2_0.exe') -or $validationShortcut.WorkingDirectory -ne $validationApp) {
        throw 'Shortcut tidak mengarah ke aplikasi terinstal.'
    }
    if ((Get-ItemProperty -LiteralPath $validationRegistry).InstallLocation.TrimEnd('\') -ne $validationApp) { throw 'Lokasi uninstall salah.' }
    if ((Get-ItemProperty -LiteralPath "$validationProtocol\shell\open\command").'(default)' -ne ('"' + (Join-Path $validationApp 'ledgy_2_0.exe') + '" "%1"')) {
        throw 'Registrasi callback aplikasi salah.'
    }
    & node (Join-Path $PSScriptRoot 'verify_windows_icons.mjs') $validationApp
    if ($LASTEXITCODE -ne 0) { throw 'Ikon pada instalasi tidak lengkap.' }
    & node (Join-Path $PSScriptRoot 'verify_windows_dependencies.mjs') $validationApp
    if ($LASTEXITCODE -ne 0) { throw 'Dependency instalasi tidak lengkap.' }
    $validationMarker = Join-Path $validationApp 'user-data-must-survive.txt'
    [IO.File]::WriteAllText($validationMarker, 'installation-test-only')
    Invoke-ValidationSetup $validationInstaller ($validationBaseArguments + ('/LOG="' + (Join-Path $validationRoot 'reinstall.log') + '"'))
    if ([IO.File]::ReadAllText($validationMarker) -ne 'installation-test-only') { throw 'Pemasangan ulang mengubah file pengguna.' }
    Write-Output "PASS: install, $($validationPayload.Count) payload hashes, Start menu shortcut, callback, icons, dependencies, and reinstall."
} finally {
    if (Test-Path -LiteralPath $validationUninstaller) {
        Invoke-ValidationSetup $validationUninstaller @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG="' + (Join-Path $validationRoot 'uninstall.log') + '"'))
    }
}
if ((Test-Path -LiteralPath (Join-Path $validationApp 'ledgy_2_0.exe')) -or (Test-Path -LiteralPath $validationRegistry) -or (Test-Path -LiteralPath $validationProtocol) -or (Test-Path -LiteralPath $validationGroupPath)) {
    throw 'Uninstall tidak membersihkan aplikasi/registrasi/shortcut uji.'
}
if ([IO.File]::ReadAllText($validationMarker) -ne 'installation-test-only') { throw 'Uninstall mengubah file pengguna.' }
Write-Output "PASS: uninstall removed only installed app files and retained the test user file. Logs: $validationRoot"
