# Fase 6 — login opsional dan sinkronisasi

Aplikasi tetap bekerja tanpa akun dan tanpa konfigurasi cloud. Buka **Pengaturan**
melalui **Setting**. Pilih **Masuk / daftar
untuk sinkron**. Layar masuk/daftar menggunakan panel glass sesuai tema Ledgy.
Halaman **profil → Detail Akun → Daftar / Login** membuka pendaftaran terlebih dahulu dan melanjutkan ke
form nama aset/saldo awal setelah sesi masuk aktif, termasuk setelah konfirmasi email.
Pengguna yang sudah masuk dapat menambah aset dari halaman **Aset**.

## Menyiapkan cloud

1. Ikuti [setup proyek dan Auth email](README.md). Aktifkan Email/password dan
   konfigurasi SMTP bila aplikasi dipakai pengguna umum.
2. Terapkan kedua migrasi secara berurutan:
   - `20261001000000_create_ledgy_backend.sql`: lima tabel, RLS, timestamp server.
   - `20261002000000_sync_window.sql`: RPC `ledgy_sync_window`, hanya dapat
     dijalankan pengguna yang masuk. Tidak menggunakan `security definer`.
3. Untuk proyek yang sudah menjalankan Fase 5, cukup terapkan migrasi kedua.
   Dengan CLI yang sudah ditautkan, gunakan `supabase db push --dry-run`, lalu
   `supabase db push`. Jangan reset database remote. Melalui SQL Editor, jalankan
   file kedua sekali sebagai query baru; jangan mengulang file pertama.
4. Salin `client-config.example.json` menjadi `client-config.local.json` dalam
   folder `supabase`, lalu isi `SUPABASE_URL` dan `SUPABASE_ANON_KEY`.
   Key publik legacy `anon` maupun `sb_publishable_...` diterima pada field itu.
   Jangan memasukkan `service_role`, `sb_secret_...`, password DB, atau token CLI.
   Aplikasi menolak key dengan role layanan; keamanan data tetap ditentukan RLS.

Untuk menyinkronkan transfer ke penerima di luar daftar aset, terapkan juga
`migrations/20261007000000_transfer_recipients.sql` setelah dua migrasi di atas.
Migrasi menambahkan nama/rekening penerima dan tetap menerima transfer antar-aset
yang sudah tersimpan. Tanpa migrasi ini, transfer penerima tetap tersimpan lokal
dan menunggu di antrean; transaksi biasa tetap kompatibel dengan skema sebelumnya.

Untuk **Detail Akun → Hapus Akun**, terapkan juga
`migrations/20261007010000_account_profile.sql`. RPC `ledgy_delete_account` hanya
menghapus akun pemanggil yang terautentikasi; foreign key menghapus ledger miliknya.
Tidak ada service key di aplikasi. Tanpa migrasi ini, penghapusan gagal dengan pesan
yang jelas dan data lokal dipertahankan. Nama, email, dan Profil Penabung memakai
API Supabase Auth yang sudah tersedia. Reset Data menyimpan tombstone agar
penghapusan dapat terkirim setelah perangkat kembali tersambung.

Jalankan dari folder Flutter, bukan `C:\Windows\system32`. Contoh PowerShell
dengan SDK tanpa spasi yang tersedia pada komputer ini:

```powershell
Set-Location -LiteralPath 'D:\7. PROYEK\6. LEDGY\ledgy'
Copy-Item -LiteralPath 'supabase/client-config.example.json' -Destination 'supabase/client-config.local.json'
```

Perintah salin hanya untuk konfigurasi pertama; jangan menimpa file yang sudah
diisi. Edit URL/key sebelum menjalankan:

```powershell
& 'D:\flutter-sdk\bin\flutter.bat' run -d windows --dart-define-from-file=supabase/client-config.local.json
& 'D:\flutter-sdk\bin\flutter.bat' devices
& 'D:\flutter-sdk\bin\flutter.bat' run -d ID_ANDROID_ANDA --dart-define-from-file=supabase/client-config.local.json
```

Untuk distribusi:

```powershell
& 'D:\flutter-sdk\bin\flutter.bat' build windows --release --no-tree-shake-icons --dart-define-from-file=supabase/client-config.local.json
& 'D:\flutter-sdk\bin\flutter.bat' build apk --release --dart-define-from-file=supabase/client-config.local.json
```

Konfigurasi dibaca saat build, bukan saat runtime; perubahan URL/key memerlukan
build ulang. Tanpa parameter konfigurasi, aplikasi tetap terbuka dalam mode lokal.
Konfigurasi contoh masih berisi placeholder dan tidak mengaktifkan cloud.

## Konfirmasi email

- Android: tambahkan **`com.ledgy.ledgy://auth/callback`** ke **Authentication →
  URL Configuration → Redirect URLs**. Manifest sudah menangani URI tersebut;
  `supabase_flutter` menerima sesi callback. Deep link bawaan router Flutter
  dinonaktifkan agar tidak merebut callback Auth.
- Windows/desktop: konfirmasi alamat lewat email, lalu kembali ke aplikasi dan
  masuk menggunakan email/password. Registrasi protokol Windows/installer belum
  dibuat, sehingga jangan mengharapkan browser otomatis membuka EXE.
  Isi **Site URL** dengan halaman HTTPS milik Anda yang benar-benar tersedia.
- Override opsional `SUPABASE_AUTH_REDIRECT_URL` dapat ditambahkan ke JSON untuk
  halaman/callback khusus, dan URL itu harus diizinkan di Dashboard serta
  benar-benar ditangani platform. Jangan memberikan override web desktop ke APK
  bila mengharapkan callback aplikasi Android.
- Jika **Confirm email** aktif, respons daftar tanpa sesi menampilkan permintaan
  mengecek email, bukan menganggap pengguna sudah masuk. Kirim ulang konfirmasi
  tersedia. Reset password tidak termasuk UI fase ini.

Lihat [Auth email/password](https://supabase.com/docs/guides/auth/passwords) dan
[redirect/deep link](https://supabase.com/docs/guides/auth/native-mobile-deep-linking).

## Perilaku sinkronisasi

- SQLite selalu menjadi sumber UI. Edit, impor CSV, penghapusan, dan transaksi
  berulang menandai baris `is_dirty=true`; antrean bertahan setelah proses mati.
- Sinkronisasi mengirim aset/kategori dahulu, lalu transaksi/anggaran/aturan.
  UUID tetap sama. Push upsert mengabaikan timestamp perangkat, mengambil
  `updated_at` server, lalu hanya membersihkan dirty jika revisi lokal belum
  berubah selama request. Edit baru dalam detik yang sama tetap antre.
- Kemudian pull semua tabel, termasuk `deleted_at`, untuk `updated_at` di atas
  cursor terakhir sampai batas waktu server dari RPC. Pagination memakai pasangan
  `(updated_at, id)`, bukan offset. Presisi timestamp server disimpan utuh dalam
  metadata SQLite, meskipun kolom waktu Drift memakai detik.
- Cursor hanya maju setelah semua tabel berhasil ditarik. Ada overlap dua detik
  untuk batas timestamp dan commit baru; baris yang sama aman dibaca ulang.
  Rancangan ini untuk transaksi REST pendek aplikasi, bukan transaksi SQL
  eksternal yang dibiarkan terbuka lama. Penulis SQL eksternal harus tetap
  mempertahankan trigger server dan menggunakan transaksi pendek.
- Konflik memakai **last-write-wins berdasarkan tulisan terakhir yang diterima
  server**, bukan waktu edit offline perangkat. Dirty lokal menerima timestamp
  saat push dan dapat menimpa versi cloud terdahulu. Ini berlaku juga untuk
  penghapusan versus edit; edit yang diterima belakangan dapat memulihkan baris.
- Penghapusan adalah tombstone `deleted_at`, tidak DELETE fisik. Hard delete lewat
  Dashboard/SQL tidak dapat disinkronkan dengan protokol ini.
- Sinkron otomatis saat membuka/aktif kembali, setelah perubahan dengan debounce
  1,2 detik, dan lewat **Sinkronkan sekarang**. Saat aktif, aplikasi juga memeriksa
  perubahan perangkat lain setiap 60 detik. Retry gagal/offline memiliki jeda
  bertahap 5–60 detik; antrean tidak dibuang. Saat aplikasi tertutup tidak ada
  sinkron cloud background; Workmanager Fase 4 hanya membuat transaksi lokal.
- Pengaturan menampilkan **Tersinkron**, **Menunggu**, **Gagal**, atau **Mode
  lokal**, jumlah antrean, pesan, dan waktu sinkron terakhir. Sesi Auth dipersist
  oleh SDK. Logout tetap bisa dilakukan offline dan tidak menghapus ledger lokal.

## Perangkat baru dan perlindungan akun

Saat pertama terhubung, ledger perangkat ditautkan ke satu UUID pengguna dan
satu proyek. Logout tidak memutus tautan atau menghilangkan data. Login akun lain
pada database yang sama **ditolak untuk sinkronisasi** agar data akun sebelumnya
tidak ikut terunggah. UI multiakun/database terpisah belum tersedia.

Perangkat baru dengan seed Tunai nol/kategori default yang belum disentuh menarik
ledger cloud tanpa mengunggah seed duplikat. Bila sudah ada data lokal nyata,
baris lokal diunggah dan digabung berdasarkan UUID, bukan mengganti ledger.
Kategori legacy dinormalisasi konsisten; aset berbeda UUID tidak digabung hanya
karena memiliki nama yang sama.

Kejadian transaksi berulang baru memiliki UUID stabil dari UUID aturan dan waktu
kejadian. Dua perangkat yang memproses kejadian sama melakukan upsert pada satu
baris, bukan membuat dua transaksi. Penanda kejadian legacy lokal tetap dihormati.

## Verifikasi

```powershell
& 'D:\flutter-sdk\bin\flutter.bat' analyze
& 'D:\flutter-sdk\bin\flutter.bat' test
npm install --prefix .dart_tool/phase5_validation --no-save --ignore-scripts @electric-sql/pglite
node supabase/tests/verify_schema.mjs
```

Tes menggunakan SQLite sungguhan, server sinkron terisolasi, dan mock API SDK:
konflik dua perangkat/jam berbeda, tombstone, perangkat baru, pagination,
respons hilang, edit selama upload, retry offline, serta antrean setelah restart.
Tes SQL memeriksa migrasi ledger, sinkronisasi, penerima transfer, dan penghapusan
akun, termasuk RLS serta perlindungan akun pengguna lain, tanpa menyentuh Supabase hosted.

Uji hosted setelah konfigurasi tersedia: masuk akun sama pada dua perangkat,
sinkron awal, edit di keduanya saat offline, sambungkan bergantian, lalu sinkron
manual untuk memeriksa pemenang berdasarkan urutan server. Hapus satu transaksi
dan periksa hilang dari UI perangkat kedua. Perangkat ketiga yang baru harus
menarik seluruh ledger tanpa menambah seed duplikat. Pengiriman email dan deep
link tetap memerlukan uji langsung pada perangkat.
