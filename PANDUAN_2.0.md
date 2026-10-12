# Dasar pengembangan Ledgy 2.0

Folder kerja baru: `D:\7. PROYEK\6. LEDGY\ledgy-2.0`.
Sumber salinan: `D:\7. PROYEK\6. LEDGY\ledgy`, versi `1.0.3+4`.

Salinan dibuat pada 8 Oktober 2026. Kode, aset, tes, lockfile dependency,
konfigurasi platform, skrip, dan dokumentasi disalin sebagai dasar pengembangan
2.0. Sebanyak 238 berkas diverifikasi identik menggunakan SHA-256. Rincian
baseline tersedia dalam `BASELINE_COPY.json`.

Versi sumber dan build Windows sekarang `2.0.0+5`. Build Android sebelumnya
tetap `2.0.0+2` sampai dibangun ulang dari sumber terbaru.
Langkah 1 quick input (model draf, validator, dan kartu konfirmasi) dan langkah 2
(parser aturan Dart murni dan memori lokal), langkah 3 (antarmuka teks dan suara),
serta langkah 4 (ParserPipeline lokal dan slot fallback nonaktif) sudah tersedia;
lihat `docs/QUICK_INPUT_STEP1.md`, `docs/QUICK_INPUT_STEP2.md`,
`docs/QUICK_INPUT_STEP3.md`, dan `docs/QUICK_INPUT_STEP4.md`.
Pemilihan otomatis Cafe / Warkop juga tersedia; lihat `docs/QUICK_INPUT_CATEGORIES.md`.
Langkah 5 menyediakan OCR struk Android dan lampiran foto lokal. Langkah 6
menyediakan Lab parser debug, korpus 120 kalimat sintetis, pengukuran akurasi,
dan catatan kegagalan lokal opsional; lihat `docs/QUICK_INPUT_STEP6.md`.

## Lokasi versi yang sudah digunakan

- Proyek stabil: `D:\7. PROYEK\6. LEDGY\ledgy`.
- Shortcut stabil: `D:\7. PROYEK\6. LEDGY\Ledgy.lnk`.
- Installer stabil: `D:\7. PROYEK\6. LEDGY\Installer Ledgy\Ledgy-Setup-1.0.3-build4-x64.exe`.

Seluruh berkas sumber, shortcut, EXE release, dan installer stabil tetap identik
setelah penyalinan. Lakukan perubahan pengembangan 2.0 di folder salinan ini.

## Persiapan pengembangan

Saat salinan pertama dibuat, cache Flutter/Gradle, folder build, output installer,
pengaturan IDE, database, konfigurasi Supabase lokal, serta kredensial
penandatanganan tidak disalin. Konfigurasi cloud dan signing kini sudah
dimigrasikan untuk pemakaian 2.0; lihat
[MIGRASI_KONFIGURASI_1_0.md](docs/MIGRASI_KONFIGURASI_1_0.md).
Gunakan `flutter pub get` dari folder ini untuk membuat konfigurasi dependency
dengan jalur baru. Aturan proyek asli disertakan pada `CHATGPT.md.txt`.

Untuk desktop, identitas 2.0 sudah dipisahkan: executable Windows/Linux memakai
`ledgy_2_0`, Linux memakai AppId `com.ledgy.ledgy2`, judul jendela menjadi
`Ledgy 2.0`, dan database Drift memakai nama `ledgy_2_0`. Dengan demikian debug
atau build desktop 2.0 tidak membuka data/database versi stabil. Untuk installer
distribusi, folder, shortcut, dan nama keluaran tetap terpisah. Sesuai keputusan
pindah ke 2.0, proyek cloud versi 1.0 sekarang digunakan juga oleh 2.0.
Android sekarang memakai applicationId `com.ledgy.ledgy2`, label
`Ledgy 2.0`, serta callback autentikasi khusus versi 2.0 untuk pemasangan
berdampingan. Fitur pemindaian struk hanya tersedia di Android.

Alur pemindaian, privasi foto, pengaturan lampiran, dan ekspor fixture debug
dijelaskan di [QUICK_INPUT_STEP5.md](docs/QUICK_INPUT_STEP5.md).

Build harian Windows dengan cloud berada di
`build/windows/x64/runner/Release/ledgy_2_0.exe`. APK rilis Android berada di
`build/app/outputs/flutter-apk/app-release.apk`. Seluruh 523 tes lulus dan analisis
kode bersih. Installer diuji di folder sementara dan dibersihkan kembali;
belum ada pemasangan untuk pemakaian pengguna atau peluncuran otomatis aplikasi.
kamera dan akurasi OCR pada perangkat Android nyata belum diuji.

Beranda menampilkan kolom Ketik transaksi langsung, dengan mikrofon dan tombol
panah. Ctrl+K pada desktop memindahkan fokus ke kolom tersebut.
