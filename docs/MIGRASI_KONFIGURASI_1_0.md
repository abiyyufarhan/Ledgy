# Konfigurasi Ledgy 2.0 dari Ledgy 1.0

Ledgy 2.0 menggunakan proyek Supabase yang sama dengan versi 1.0. Login dengan
email/password akun lama; tidak perlu membuat proyek atau akun cloud baru.
Sinkronisasi menggabungkan ledger lokal 2.0 dengan data cloud akun tersebut.
Perubahan dan penghapusan yang disinkronkan dapat terlihat di versi 1.0 jika
versi tersebut masih dipakai dengan akun yang sama.

## Konfigurasi yang disalin

- `supabase/client-config.local.json`: Project URL dan key publik klien.
- `android/key.properties` serta `release-private/ledgy-upload.jks`: signing APK
  rilis, dengan file keystore tersalin ke folder privat Ledgy 2.0.
- Skema SQL versi 1.0 tetap kompatibel; tidak ada migrasi SQL baru, reset, atau
  perubahan data cloud yang dijalankan dalam migrasi konfigurasi ini.

File sumber versi 1.0 tetap dipertahankan. Database, password kunci lokal,
preferensi pengguna, dan sesi login versi 1.0 tidak disalin. Data lokal Ledgy 2.0
yang sudah ada tetap dipakai. Data versi 1.0 yang belum terkirim ke cloud perlu
disinkronkan dari versi 1.0 agar dapat ditarik oleh versi 2.0.

## Identitas aplikasi

- Database lokal: `ledgy_2_0`.
- Android: `com.ledgy.ledgy2`, label Ledgy 2.0.
- Windows: `ledgy_2_0.exe`, folder instalasi `%LOCALAPPDATA%/Programs/Ledgy 2.0`,
  shortcut Ledgy 2.0, serta identitas installer/notifikasi yang terpisah.
- Sesi Auth dan verifier PKCE memakai namespace khusus 2.0 per proyek cloud.

Untuk konfirmasi email Android, tambahkan URL berikut pada proyek Supabase
lama di **Authentication → URL Configuration → Redirect URLs** sambil
mempertahankan callback versi 1.0:

```text
com.ledgy.ledgy2://auth/callback
```

Login email/password akun yang sudah dikonfirmasi tidak memerlukan callback ini.
Daftar URL Dashboard tidak dapat diubah dengan key publik klien; perubahan itu
memerlukan akses admin proyek. Pengaturan SMTP dari proyek lama tetap digunakan.

## Build yang selalu menyertakan konfigurasi

Jalankan dari PowerShell:

```powershell
Set-Location -LiteralPath 'D:\7. PROYEK\6. LEDGY\ledgy-2.0'
& ./tool/build_configured.ps1 -Target windows
& ./tool/build_configured.ps1 -Target android
```

Skrip memvalidasi konfigurasi publik dan selalu mengirim
`--dart-define-from-file=supabase/client-config.local.json`. Build Flutter biasa
tanpa parameter tersebut menghasilkan aplikasi mode lokal.

Windows release: `build/windows/x64/runner/Release/ledgy_2_0.exe`.
Installer: `build/releases/Ledgy-2.0-Setup-2.0.0-build2-x64.exe`.
APK release: `build/app/outputs/flutter-apk/app-release.apk`.

Jika perangkat Android masih memakai APK **debug** dari tahap pengembangan,
APK release memakai sertifikat berbeda dan tidak bisa langsung memperbaruinya.
Gunakan build debug terkonfigurasi untuk memperbarui aplikasi itu tanpa
menghapus data lokal:

```powershell
& ./tool/build_configured.ps1 -Target android-debug
& 'C:\Users\abiyy\AppData\Local\Android\sdk\platform-tools\adb.exe' install -r 'build/app/outputs/flutter-apk/app-debug.apk'
```

Jangan hapus instalasi debug sebelum memastikan transaksi lokal telah
tersinkron/tercadangkan. APK release ditujukan untuk pemasangan baru atau
pembaruan APK release 2.0 yang ditandatangani keystore yang sama.

## Pemeriksaan setelah membuka aplikasi

1. Buka build terkonfigurasi, lalu masuk dengan akun Ledgy lama.
2. Periksa **Pengaturan → Sinkronisasi** sampai antrean selesai.
3. Periksa akun, transaksi, dan saldo setelah data cloud ditarik.

Migrasi konfigurasi tidak menyertakan email/password pengguna atau menyalin sesi
login. Pengujian login dan sinkronisasi akun nyata memerlukan login pengguna
sendiri. Jangan membagikan folder `release-private`, keystore, atau key.properties.
Installer/APK hanya menyertakan konfigurasi publik klien yang memang diperlukan.

Build rilis Android memakai aturan R8 khusus delapan kelas model OCR opsional
yang dilaporkan oleh `missing_rules.txt`. Backend struk selalu meminta
`TextRecognitionScript.latin`; model aksara lain memang `compileOnly` pada
plugin dan tidak digunakan oleh aplikasi. Optimasi rilis tetap aktif.
Referensi: [plugin Text Recognition](https://github.com/flutter-ml/google_ml_kit_flutter/tree/master/packages/google_mlkit_text_recognition)
dan [penanganan missing classes R8](https://developer.android.com/build/releases/past-releases/agp-7-0-0-release-notes#r8-missing-class-warnings).
