# Fase 8 — persiapan rilis Ledgy

## Perubahan

- Logo dompet vektor original, PNG 1024 px, launcher density Android, adaptive /
  monochrome icon, Windows ICO 16–256 px, Linux PNG dan contoh desktop entry.
- Splash Android native (termasuk Android 12+) dan startup Flutter untuk semua
  platform; loading/error + retry, tanpa data transaksi atau delay buatan.
- Signing rilis Android dari key.properties atau environment secrets; release
  gagal jika key tidak tersedia, debug/test tetap dapat digunakan.
- Generator key tidak overwrite, password acak tidak dicetak, file signing
  diabaikan Git dan izin Windows dibatasi pengguna pemilik + SYSTEM.
- GitHub Actions quality gate, desktop matrix, Android compile tanpa secret di
  PR, signed Android release hanya workflow_dispatch/environment terlindungi.
- README setup lokal, Supabase + kedua migrasi, callback, signing, distribusi,
  CI secrets, dan backup/pemulihan dengan batasan yang dinyatakan eksplisit.

## Verifikasi

- `flutter analyze --no-pub`: tidak ada masalah.
- `flutter test --no-pub`: seluruh **89 tes lulus**, termasuk startup private,
  retry error dan splash pada font 200%.
- Generator logo/PNG/ICO: lulus; aset 512 px Play Store juga tersedia.
- Parser YAML: 4 job valid, permission read-only dan action dipin SHA commit.
- `flutter build windows --release --no-pub` dengan config lokal: berhasil;
  build akhir selesai dalam 373,7 detik. Seluruh folder Release harus disertakan.

- `flutter build apk --release --no-pub`: berhasil (741,3 detik), APK
  **68.298.552 byte** / sekitar 65,1 MiB.
- `apksigner verify`: valid APK signature v2, satu signer RSA 4096,
  `CN=Ledgy Release, OU=Ledgy, O=Ledgy, C=ID`; bukan Android debug certificate.
- APK mengandung `ledgy_launch`, `ledgy_foreground` dan adaptive launcher;
  application label **Ledgy**, version 1.0.0+1, min SDK 24, target SDK 36.
- ZIP Windows portable **15.141.319 byte**; EXE, DLL dan data lengkap, tanpa
  file database/keystore/properties privat. AOT Windows dibuat setelah perubahan
  startup terakhir, bukan artifact rilis lama.

- `flutter build appbundle --release --no-pub`: berhasil (360,9 detik), AAB
  **66.697.706 byte** / sekitar 63,6 MiB.
- `jarsigner -verify`: AAB valid; fingerprint sertifikat AAB, APK, dan alias
  `ledgy-upload` pada keystore lokal identik:
  `59e0acfd998dc29ba54ed1fa8d860b63e479e6a1dee451a54172a3b6945dd67a`.
- Checksum APK/AAB/ZIP tersedia di `build/releases/SHA256SUMS.txt`.
- Skrip PowerShell rilis: parsing sintaks lulus. Kredensial dan password tidak
  dicetak saat pembuatan/verifikasi keystore.

Linux belum dapat
dibangun lokal karena host Windows tidak memiliki Linux/WSL; workflow Linux
disiapkan, tetapi belum dijalankan di GitHub. Belum ada publikasi ke Play Store,
sertifikat Windows Authenticode atau perubahan proyek Supabase live. Installer Windows
kini tersedia; lihat [panduan installer Windows](WINDOWS_INSTALLER.md) untuk hasil
dan verifikasi terbaru.

## Artifact lokal

- `build/app/outputs/flutter-apk/app-release.apk`: instalasi Android langsung.
- `build/app/outputs/bundle/release/app-release.aab`: unggah Google Play.
- `build/releases/ledgy-windows-1.0.0+1-x64.zip`: bundle Windows portable lengkap.
- `build/releases/SHA256SUMS.txt`: checksum integritas ketiga berkas.
- `assets/branding/ledgy-play-store-512.png`: ikon untuk materi store.

Build memakai `supabase/client-config.local.json` yang sudah ada (URL/key publik).
Tidak ada migrasi Supabase remote yang dijalankan. APK tidak diinstal ke perangkat
yang tersambung dan data lokal pengguna tidak diubah/dihapus.

Warning nonfatal selama build: NuGet memakai fallback/cache di Windows;
workmanager masih memakai Kotlin Gradle Plugin (perlu upgrade kompatibel pada
Flutter mendatang), Android CLI mengingatkan versi SDK XML, dan tree-shaking
menyebut font CupertinoIcons yang tidak dibundel. Semua build akhir exit 0;
ikon Ledgy dan MaterialIcons serta signature APK sudah diverifikasi. Tidak ada
dependency baru ditambahkan untuk menyembunyikan warning tersebut.

## Keamanan migrasi instalasi

APK lama memakai key debug. Key rilis baru berbeda; jangan uninstall instalasi
berisi data hanya agar APK dapat dipasang. Ekspor CSV bukan backup penuh.
Periksa sinkronisasi cloud dan rencana pemulihan sebelum berganti signature.
Keystore adalah identitas rilis: backup terenkripsi keystore + password, jangan
commit atau regenerate untuk build selanjutnya.

Enkripsi database/backup masih tertunda dari Fase 7 dan tidak ditambahkan pada
fase rilis ini. Uji fisik keamanan dan performa tetap diperlukan.

Referensi: [Flutter Android release](https://docs.flutter.dev/deployment/android),
[Android splash](https://docs.flutter.dev/platform-integration/android/splash-screen),
[Flutter Linux](https://docs.flutter.dev/deployment/linux),
[GitHub Actions security](https://docs.github.com/en/actions/reference/security/secure-use).
