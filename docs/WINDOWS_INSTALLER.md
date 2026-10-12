# Installer Windows Ledgy 2.0

Versi 2.0.0+5 memakai konfigurasi cloud Ledgy 1.0. Login menggunakan akun lama;
data cloud akun yang sama disinkronkan di kedua versi jika keduanya tetap dipakai.

Installer: `build/releases/Ledgy-2.0-Setup-2.0.0-build5-x64.exe`.
Salinan untuk dibagikan ditempatkan di folder induk `Installer Ledgy 2.0`.
Windows 10 1809 / Windows 11 x64 didukung. Runtime Visual C++ disertakan;
penerima tidak perlu memasang Flutter atau Visual Studio.

Instalasi memakai `%LOCALAPPDATA%/Programs/Ledgy 2.0`, shortcut **Ledgy 2.0**,
executable `ledgy_2_0.exe`, identitas uninstall dan protokol `com.ledgy.ledgy2`.
Installer Ledgy 1.0, folder pemasangan lama, dan shortcut Ledgy lama tidak diganti.
Database lokal 2.0 tetap `ledgy_2_0`; sesi login dan notifikasi memakai identitas 2.0.

Build installer dari bundle release yang telah menyertakan cloud:

```powershell
& ./tool/build_configured.ps1 -Target windows
& ./tool/package_installer.ps1 -CompilerPath '../ledgy/build/installer-tools/InnoSetup/ISCC.exe'
```

Jika compiler belum ada, berikan path ISCC.exe dari instalasi Inno Setup Anda.
Installer tidak menyertakan database pembuat, key.properties, keystore, atau
berkas konfigurasi privat. URL dan key publik Supabase sudah dikompilasi ke aplikasi.
Installer belum memakai sertifikat Authenticode penerbit aplikasi.

Panduan migrasi konfigurasi, callback konfirmasi Android, login, dan penjelasan
sinkronisasi: [MIGRASI_KONFIGURASI_1_0.md](MIGRASI_KONFIGURASI_1_0.md).
