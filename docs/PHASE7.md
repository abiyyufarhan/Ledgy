# Fase 7 — keamanan dan penyempurnaan

## Kunci aplikasi

Aktifkan **Pengaturan → Keamanan & privasi → Password dan/atau Biometrik**.
Password Ledgy menerima 8–128 karakter (huruf, angka, simbol), terpisah dari
password akun Supabase. Pengubahan/penonaktifan meminta password saat ini.
Jika kedua metode aktif, salah satunya dapat membuka aplikasi.

Biometrik diperiksa sebelum switch dapat diaktifkan dan dicek ulang saat membuka
kunci. Android/macOS memerlukan biometrik yang terdaftar; Windows memerlukan
unit biometrik yang dilaporkan Windows Biometric Framework serta dukungan Hello.
Windows Hello dapat menawarkan PIN karena API Windows tidak dapat memaksakan
metode biometrik saja. Tanpa dukungan, opsi biometrik tetap tidak dapat diaktifkan.
Pengaturan kunci perangkat dari versi lama tetap dapat membuka aplikasi agar
pembaruan tidak mengunci pengguna di luar aplikasinya. Linux dapat memakai
password; biometrik tetap tidak tersedia melalui `local_auth`.

Password disimpan sebagai PBKDF2-HMAC-SHA256 (600.000 iterasi, salt acak 16 byte,
hasil 32 byte) memakai `cryptography`, dengan derivasi di isolate. Record hash
hanya disimpan di state lokal, tidak masuk sinkronisasi/CSV. Setelah lima
password yang salah, jeda 30 detik disimpan hingga restart aplikasi. Pengaturan
kedua metode disimpan bersama dalam satu record, dan error baca tetap menutup
konten aplikasi. Lihat [catatan pengaturan terbaru](SETTINGS_SECURITY.md).

Setelah aktivasi, Ledger ditutup saat aplikasi dibuka dan setelah kembali dari
latar belakang. Tekan **Buka Ledgy** untuk memverifikasi identitas. Pembatalan,
error plugin, dan autentikasi yang selesai setelah masuk background tidak membuka
data. Penutup juga menyembunyikan konten saat inactive. Ini pengaman tampilan,
bukan pengganti enkripsi file atau keamanan sistem operasi.

## Privasi

Tidak ada SDK analitik pada dependency aplikasi. Data keuangan dikirim hanya
melalui sinkronisasi Supabase ketika pengguna login. Error otomatisasi tidak
dicetak mentah. Error UI pemuatan data diganti pesan umum dengan retry.
Pelaporan error Flutter/platform membuang exception, stack, dan diagnostic
collector asli sebelum menampilkan pesan umum di konsol. Peringatan anggaran
memakai visibility private pada layar terkunci Android.
Android Auto Backup dimatikan melalui `allowBackup=false`; backup pribadi
harus dibuat secara eksplisit. Pengujian source memeriksa bahwa `lib` tidak
memanggil `print`, `debugPrint`, atau `log`.

## Enkripsi — belum diaktifkan

Database lokal saat ini masih SQLite biasa. Backup terenkripsi belum tersedia.
Jangan menganggap CSV sebagai backup terenkripsi: CSV terbuka dan hanya memuat
transaksi, bukan seluruh ledger.

Implementasi SQLCipher dan backup belum dilakukan. Permintaan password aplikasi
terbaru menggunakan dependency `cryptography` untuk hash password, tanpa mengubah
database menjadi SQLCipher atau menambahkan backup terenkripsi.

Rancangan berikutnya: kunci acak perangkat di secure storage; SQLCipher dibundel
melalui hook sqlite3; migrasi database lama diverifikasi sebelum penggantian;
backup seluruh tabel memakai AES-GCM dan derivasi kunci dari password pengguna,
dengan pratinjau serta validasi sebelum restore. Proses background juga harus
membuka database memakai kunci yang sama. Enkripsi tidak boleh mengganggu antrean
sinkron yang sudah tersimpan.

Referensi: [sqlite3 build hooks](https://pub.dev/documentation/sqlite3/latest/topics/hook-topic.html),
[SQLCipher API](https://www.zetetic.net/sqlcipher/sqlcipher-api/),
[local_auth](https://pub.dev/packages/local_auth).

## Aksesibilitas

Area sentuh profil menjadi 48 px; ikon avatar tetap vektor 24 px. Tombol icon,
teks, dan outline memakai area minimal 48 px. Warna teks sekunder dibuat lebih
jelas; tombol utama memakai biru lebih gelap untuk menjaga kontras tulisan putih.
Kartu aset pada layar kecil atau font besar memakai tinggi yang mengikuti isi.
Empty state bisa digulir, tab Anggaran tidak lagi memakai tinggi kaku. Font tidak
dibatasi skalanya. Pengujian mencakup tujuh halaman pada lebar 400 px dan font 200%,
serta empty state pada layar 360 × 500.

## Audit blur dan performa

Pengujian `test/security_ui_test.dart` menghitung BackdropFilter yang terlihat
dan menghasilkan `build/audits/phase7-blur.json`.

| Layar | Batas blur terlihat, menu tertutup |
| --- | ---: |
| Beranda | 0 |
| Transaksi | 0 |
| Anggaran / berulang | 0 |
| Aset | 0 |
| Analisis | 0 |
| Pengaturan | 1 |
| Login / daftar | 1 |
| Kunci aplikasi | 1 |
| Menu terbuka / picker kategori | Tambahan 1 |

RepaintBoundary melindungi backdrop, chart, avatar, tombol hover, panel, dan kartu
tanpa blur. Baris daftar tidak memasang BackdropFilter. Animasi hover/menu/sidebar
dipendekkan ke 160 ms; menu/hover/sidebar menghormati reduced motion. Boundary
membatasi area repaint, tetapi bukan jaminan FPS pada semua perangkat.

### Uji Android fisik yang masih diperlukan

Pada 5 Oktober 2026, `flutter devices` hanya menemukan Windows, Chrome, dan Edge.
Tidak ada Android tersambung. Uji performa Android kelas menengah belum dilakukan;
widget test bukan pengganti pengukuran GPU/perangkat.

1. Sambungkan Android kelas menengah dengan USB debugging.
2. Jalankan `flutter run --profile -d ID_PERANGKAT` (sertakan dart defines Supabase
   hanya jika menguji cloud). Jangan menilai FPS dari mode debug.
3. Dalam DevTools Performance, rekam scrolling Beranda/Transaksi selama 30 detik,
   buka-tutup menu dan picker 10 kali, berpindah tab, dan rotasi layar.
4. Gunakan ledger uji 1.000–10.000 transaksi tanpa data pengguna nyata.
5. Catat model perangkat, RAM, refresh rate, median/p95 UI dan raster frame time,
   janky frames, serta memori. Target awal pada 60 Hz: frame UI/raster di bawah
   16,7 ms untuk sebagian besar frame; simpan trace untuk mengevaluasi outlier.
6. Uji kunci setelah cold start, Home → kembali, panggilan masuk, pembatalan
   biometrik, PIN perangkat, dan font Android maksimal.

## Validasi

Hasil verifikasi kode pada 5 Oktober 2026: `flutter analyze --no-pub` tanpa isu
dan `flutter test --no-pub` lulus 85 tes. Hitungan blur aktual sesuai tabel
untuk tujuh halaman dengan menu tertutup dan font 200%.
Build APK release dengan konfigurasi Supabase lokal juga berhasil (65,6 MB),
termasuk kompilasi perubahan Kotlin dan tema biometrik Android. APK ada di
`build/app/outputs/flutter-apk/app-release.apk`; pasang sebagai pembaruan, tanpa
menghapus data aplikasi. Build Windows belum diulang pada fase ini.

Jalankan `flutter analyze` dan `flutter test`. Tes mencakup kunci gagal tertutup,
persistensi pengaturan, hasil autentikasi yang terlambat, penutup konten dan
lifecycle, area sentuh, font besar, serta batas blur. Biometrik dan performa masih
memerlukan verifikasi fisik sebelum rilis.
