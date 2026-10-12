# Ledgy

Pencatatan keuangan pribadi **offline-first** untuk Android, Windows, dan Linux,
dengan login Supabase opsional untuk sinkronisasi. Uang disimpan sebagai rupiah
bulat, waktu UTC, dan transfer tidak dihitung sebagai pemasukan/pengeluaran.

## Menjalankan aplikasi

Gunakan Flutter **3.47.5 / Dart 3.13.4** (versi yang dipin di CI). Semua perintah
di README dijalankan dari folder `ledgy` yang memuat `pubspec.yaml`.
Pada Windows, gunakan SDK tanpa spasi dan perbaiki PATH agar SDK lama tidak terpilih:

```powershell
Set-Location -LiteralPath 'D:\7. PROYEK\6. LEDGY\ledgy'
$env:Path = 'D:\flutter-sdk\bin;' + $env:Path
flutter doctor -v
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
flutter run -d windows
```

Mode lokal berjalan tanpa konfigurasi cloud. Untuk Android, aktifkan Developer
Options/USB debugging, sambungkan perangkat, lalu `flutter devices` dan
`flutter run -d ID_PERANGKAT`. Windows membutuhkan Visual Studio dengan workload
**Desktop development with C++**, Windows SDK dan CMake; Android membutuhkan
Android SDK, JDK, serta lisensi SDK yang telah diterima.

### Sidebar desktop

Pada jendela selebar minimal 700 px, sidebar dimulai dengan ikon saja (64 px).
Arahkan kursor ke sidebar untuk membuka label (232 px); kursor keluar menutupnya
kembali setelah jeda pendek. Klik logo/header Ledgy untuk menyematkan atau
melepas sidebar. Keyboard Tab membuka label, dan Escape menutup/melepas sematan.
Pada layar ponsel, navigasi utama ditampilkan di bagian bawah.

Sidebar menampilkan logo/versi, profil pengguna dan badge profil penabung, lalu
Dashboard, Transaksi, Anggaran, Aset, dan Setting. Tombol tambah di bagian
bawah melebar menjadi `+ Transaksi` saat hover atau fokus keyboard. Menu profil
dipindahkan dari kanan atas ke sidebar; pada ponsel, akses profil berada di kiri
header halaman.

Klik kartu atau ikon profil untuk membuka **Detail Akun**. Halaman ini menampilkan
avatar, nama, email, pilihan **Profil Penabung**, dan **Keluar dari aplikasi**.
Nama dan profil penabung diperbarui melalui Supabase Auth; perubahan email
memerlukan konfirmasi email. **Reset Data** mempertahankan akun serta mengantrekan
penghapusan ledger untuk sinkronisasi. **Hapus Akun** meminta ketikan `HAPUS`,
menghapus akun cloud terlebih dahulu, lalu membersihkan data lokal. Terapkan
[migrasi penghapusan akun](supabase/migrations/20261007010000_account_profile.sql)
agar tombol Hapus Akun dapat digunakan; tidak ada penghapusan saat membuka halaman.

Dashboard menampilkan saldo seluruh aset, arus kas dan rasio tabungan per bulan,
grafik Keseluruhan/Mingguan/Bulanan/Tahunan, progres anggaran, serta transaksi terakhir. Pilihan
bulan berlaku pada ringkasan dan tautan ke transaksi/anggaran. Keseluruhan mencakup
tanggal transaksi aktif pertama hingga terakhir, tanpa mengikuti bulan pilihan.
Mingguan mengikuti bulan pilihan, Bulanan mengikuti tahun pilihan, dan Tahunan
merangkum riwayat hingga tahun pilihan. Periode tanpa transaksi menjadi celah;
data tunggal ditampilkan sebagai titik tanpa garis ke nol. Pencarian mencakup
catatan, kategori, aset, dan nominal transaksi di seluruh periode. Alamat lama
`/analysis` dan `/reports` diarahkan ke Dashboard.

Panel utama Dashboard menggunakan ukuran yang seragam dalam grid responsif dan
permukaan glass Ledgy. Isi anggaran, transaksi, target tabungan, dan aset memakai
scrollbar masing-masing ketika melebihi ruang panel; penambahan data tidak
memperbesar panel. Kartu ringkasan juga memiliki ukuran seragam dalam kelompoknya.

Target tabungan dapat dibuat, diubah, dan dihapus dari Dashboard. Jumlah terkumpul
diperbarui secara manual tanpa mengubah saldo aset. Target disimpan secara lokal
di perangkat dan belum termasuk sinkronisasi cloud.

Saat mendaftar akun, pilih Konservatif/Pasif, Moderat/Terencana, Agresif/Frugal,
Oportunistik/Situasional, atau Penabung Impulsif. Pilihan disimpan sebagai kode
`saver_profile` pada metadata Supabase Auth, dan dibaca saat login di perangkat
lain; fitur ini tidak memerlukan migrasi SQL baru. Akun lama tanpa metadata
menampilkan `Profil belum dipilih` dan dapat memilih melalui Detail Akun atau Setting. Pembaruan
profil memerlukan internet; jika gagal, pilihan terakhir tersimpan tetap dipakai.

Transisi 240 ms memakai satu pengendali animasi dan ikon dengan posisi tetap.
Saat hover, sidebar melapisi konten tanpa mengubah layout grafik setiap frame;
saat disematkan, konten mendapatkan ruang tersendiri. Tidak ada BackdropFilter
tambahan. Preferensi sistem mengurangi animasi juga dihormati.

### Halaman Transaksi

Form Transaksi Baru memiliki kolom berukuran seragam, tanggal/jam format 24 jam,
dan Catatan beberapa baris. Pada Masuk, pilihan aset berlabel Menuju Akun dan
kategori pemasukan terdiri dari Acara Sosial, Pemasukan, Pencairan Pinjaman,
Tabungan, dan Lainnya beserta subkategorinya. Pada Transfer, isi Nama Penerima
dan Rekening Penerima; nomor disimpan sebagai teks agar nol awal tetap utuh.
Transfer ini mengurangi saldo akun asal dan tidak menambahkan aset penerima.
Riwayat transfer antar-aset sebelumnya tetap dapat dibaca. Detail penerima
tersedia di riwayat, laporan Excel/PDF, dan ekspor/impor CSV.

Halaman dibuka pada bulan berjalan. Ikon kalender membuka tiga pilihan periode:
Harian, Bulanan, dan Tahunan. Ringkasan pemasukan dan pengeluaran mengikuti periode
serta filter aktif; transfer tetap terlihat pada pilihan Semua, tetapi tidak
menambah kedua total. Panah kiri/kanan berpindah hari, bulan, atau tahun sesuai
pilihan periode. Riwayat periode sebelumnya tetap tersimpan dan bisa dilihat kembali.

Ikon corong membuka dialog glass dengan tipe Pemasukan/Pengeluaran, kategori dan
subkategori (termasuk kategori pribadi), serta akun pengguna. Pilih kategori induk
untuk mencakup semua subkategorinya. Reset mengosongkan pilihan di dialog; tekan
Terapkan untuk mengubah daftar. Menutup dialog tanpa menerapkan tidak mengubah
filter aktif. Tidak ada lagi kolom pencarian atau baris filter lama.

Kolom Tipe Transaksi, Semua Kategori, dan Semua Akun ditampilkan tanpa ikon di sebelah kiri.
Ikon unduh membuka dropdown berjudul Download Laporan, dengan pilihan Excel (.xlsx)
di atas PDF (.pdf), garis pemisah putih, dan sudut membulat. Laporan berisi ringkasan
dan transaksi yang sedang ditampilkan sesuai periode serta filter aktif. Nominal
pada Excel berupa angka agar bisa dihitung, dan catatan tetap berupa teks.
Ekspor seluruh data dan impor CSV dengan pratinjau tetap tersedia melalui tab Anggaran.

## Menyiapkan Supabase

1. Buat proyek Supabase dan simpan password database di pengelola password.
2. Terapkan **kedua** migrasi, berurutan: `20261001000000_create_ledgy_backend.sql`
   lalu `20261002000000_sync_window.sql`. Migrasi kedua menyediakan RPC sinkronisasi;
   tanpa ini login bisa berhasil tetapi sinkronisasi gagal.
3. Aktifkan provider Email dan konfirmasi email. Untuk penerima umum, atur Custom
   SMTP. Redirect URLs Android: `com.ledgy.ledgy://auth/callback`. Site URL harus
   halaman web yang benar-benar tersedia, bukan `localhost:3000` untuk pengguna
   rilis. Desktop saat ini melakukan konfirmasi email lalu login manual.
4. Salin konfigurasi contoh dan isi **Project URL + anon/publishable key publik**:

```powershell
Copy-Item supabase/client-config.example.json supabase/client-config.local.json
# Edit client-config.local.json dengan editor Anda.
flutter run -d windows --dart-define-from-file=supabase/client-config.local.json
```

Konfigurasi ini dibaca **saat build**, bukan saat aplikasi berjalan. APK/EXE harus
dibangun ulang setelah konfigurasi berubah. Jangan masukkan `service_role`,
`sb_secret_...`, access token CLI, atau password database ke aplikasi maupun CI
client variables. Key publik memang berada dalam binary; keamanan data bergantung
pada Auth dan RLS. Jangan menonaktifkan RLS untuk mengatasi masalah sinkronisasi.

Alternatif CLI (setelah CLI tersedia):

```powershell
supabase init # hanya jika config.toml belum ada
supabase login
supabase link --project-ref PROJECT_REF_ANDA
supabase db push --dry-run
supabase db push
supabase migration list
```

Jangan menjalankan ulang SQL di proyek yang sudah memiliki tabel tanpa memeriksa
riwayat migrasi. Panduan lengkap: [backend/Auth](supabase/README.md) dan
[sinkronisasi/callback](supabase/SYNC.md). Verifikasi sinkronisasi dua perangkat
dengan akun yang sama sebelum menyebarkan rilis; build sukses tidak membuktikan
bahwa migrasi remote telah diterapkan.

## Ikon dan splash

Logo dompet Ledgy berupa vektor biru/cyan dengan latar navy, tanpa dependency baru.
Android memakai adaptive icon, monochrome icon Android 13+, splash native sebelum
frame pertama, dan splash Flutter selama inisialisasi. Desktop memakai ikon
Windows multi-resolusi/Linux PNG serta splash Flutter yang sama. Tidak ada
penundaan splash buatan atau data keuangan pada splash.

Source: `lib/core/branding/ledgy_mark.dart` dan vector drawable Android. Aset PNG
dan ICO sudah tersedia di repo; regenerasi setelah mengubah desain:

```powershell
flutter test tool/generate_brand_assets.dart
```

Vector drawable Android harus ikut disesuaikan jika bentuk logo diubah.
`assets/branding/ledgy-icon-1024.png` adalah master raster, bukan dependency
runtime. `assets/branding/ledgy-play-store-512.png` adalah versi 512 px berlatar penuh untuk
[persyaratan Google Play](https://developer.android.com/distribute/google-play/resources/icon-design-specifications).

## Signing dan build rilis Android

Keystore lokal dibuat oleh `tool/create_keystore.ps1` dengan RSA 4096, alias
`ledgy-upload`, password acak, dan masa berlaku 10.000 hari. Generator tidak
menimpa key yang sudah ada dan tidak mencetak password. Jika belum memiliki key:

```powershell
# Ambil lokasi JDK/keytool dari flutter doctor -v, lalu sesuaikan path ini.
./tool/create_keystore.ps1 -Keytool 'D:\1. APLIKASI\Andrid SDK\jbr\bin\keytool.exe'
```

Simpan `release-private/ledgy-upload.jks` **dan** `android/key.properties` pada
backup terenkripsi terpisah; password terdapat di file properties, jangan tampilkan
di terminal, screenshot, atau chat. Jangan membuat key baru untuk setiap build.
Keduanya diabaikan Git. Konfigurasi contoh: `android/key.properties.example`.
Gradle menolak build rilis jika signing tidak lengkap; tidak ada fallback key debug.

```powershell
flutter build apk --release --dart-define-from-file=supabase/client-config.local.json
flutter build appbundle --release --dart-define-from-file=supabase/client-config.local.json
```

Untuk distribusi lokal tanpa login, hapus argumen `--dart-define-from-file`.
Hasilnya:

- APK untuk install langsung: `build/app/outputs/flutter-apk/app-release.apk`.
- AAB untuk Google Play: `build/app/outputs/bundle/release/app-release.aab`.

Naikkan `version` di `pubspec.yaml` (misalnya `1.0.1+2`) sebelum update rilis;
versionCode harus meningkat di Google Play. Daftarkan Play App Signing jika
distribusi melalui Play Store. Jangan mengunggah keystore sebagai artifact CI.

**Penting untuk instalasi lama:** APK sebelum Fase 8 memakai key debug. APK dengan
key rilis baru tidak bisa menimpa aplikasi dengan tanda tangan berbeda. Jangan
langsung uninstall: data lokal akan hilang. Backup/ekspor dan pastikan sinkron
berhasil dahulu; CSV saja bukan backup penuh. APK sideload dan APK dari Play juga
bisa berbeda key jika memakai Play App Signing.

```powershell
flutter devices
adb -s ID_PERANGKAT install -r build/app/outputs/flutter-apk/app-release.apk
```

AAB tidak dapat diinstal langsung seperti APK. Jika `INSTALL_FAILED_UPDATE_INCOMPATIBLE`,
jangan memaksa uninstall sebelum memiliki rencana pemulihan data.
Lihat [panduan signing/build resmi Flutter](https://docs.flutter.dev/deployment/android).

## Build desktop

Tutup Ledgy sebelum build Windows supaya linker tidak terkunci (`LNK1104`).

```powershell
flutter build windows --release --no-tree-shake-icons --dart-define-from-file=supabase/client-config.local.json
```

Untuk distribusi dengan instalasi, jalankan `./tool/package_installer.ps1` setelah
build. Hasilnya `build/releases/Ledgy-Setup-<versi>-build<build>-x64.exe`;
bagikan satu berkas installer tersebut. Lihat [panduan installer Windows](docs/WINDOWS_INSTALLER.md).
Installer belum memiliki sertifikat Authenticode; Windows SmartScreen dapat
memberi peringatan penerbit tidak dikenal.

Untuk distribusi portable, kirim **seluruh** folder `build/windows/x64/runner/Release`,
bukan EXE saja: DLL dan folder `data` diperlukan.
Untuk membuat ZIP portable lengkap beserta hash: `./tool/package_windows.ps1`.
Arsip disimpan di `build/releases` dan tidak menimpa arsip versi yang sudah ada.
Setelah APK/AAB/ZIP selesai, `./tool/release_checksums.ps1` menghasilkan
`build/releases/SHA256SUMS.txt` untuk memeriksa integritas berkas.

Linux harus dibangun pada Linux (tidak bisa cross-build langsung dari Windows).
Di Ubuntu 24.04 dengan Flutter 3.47.5 dan JDK tersedia:

```bash
sudo apt-get update
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev openjdk-17-jdk
flutter pub get --enforce-lockfile
flutter build linux --release --dart-define-from-file=supabase/client-config.local.json
./build/linux/x64/release/bundle/ledgy
```

Distribusikan seluruh `build/linux/x64/release/bundle`; paket tar.gz menjaga izin
executable. File `.desktop` contoh disertakan di `data`, namun perlu menyesuaikan
`Exec` dengan lokasi instalasi dan memasang ikon `ledgy.png` sebagai
`~/.local/share/icons/hicolor/256x256/apps/com.ledgy.ledgy.png` serta desktop entry
di `~/.local/share/applications`. Jangan memakai literal path build pada installer.
Kunci `local_auth` belum mendukung Linux; jangan menjanjikan biometrik/PIN pada Linux.

## GitHub Actions

Workflow ada di [.github/workflows/ci.yml](.github/workflows/ci.yml). Jadikan
folder **ledgy** sebagai root repository GitHub (workflow harus berada di
`REPO_ROOT/.github/workflows`, bukan subfolder). Jika monorepo, pindahkan workflow
ke root dan atur working directory/path setiap job ke `ledgy`.

- Push/PR: analyze, unit/widget test, coverage, build Windows/Linux release,
  dan compile APK **debug** tanpa key rilis.
- Actions → **Ledgy CI → Run workflow → release_android=true**: APK dan AAB
  bertanda tangan, verifikasi signature, SHA-256, dan artifact unduhan.
- Versi Flutter dan commit action dipin; workflow hanya punya `contents: read`,
  tidak auto-deploy, dan tidak menggunakan `pull_request_target`.

Di Settings → Environments buat **android-release**, batasi branch rilis dan
aktifkan required reviewers bila tersedia. Tambahkan environment secrets:

| Secret | Isi |
| --- | --- |
| `LEDGY_KEYSTORE_BASE64` | Base64 dari keystore yang sama, tanpa baris tambahan |
| `LEDGY_KEY_ALIAS` | `ledgy-upload` |
| `LEDGY_STORE_PASSWORD` | `storePassword` dari file lokal |
| `LEDGY_KEY_PASSWORD` | `keyPassword` dari file lokal |

Untuk menyalin base64 langsung ke clipboard, tanpa mencetak di konsol:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path 'release-private/ledgy-upload.jks'))) | Set-Clipboard
# Paste ke secret GitHub, lalu kosongkan clipboard.
Set-Clipboard -Value ''
```

Repository **Variables** (bukan service secrets): `SUPABASE_URL` dan
`SUPABASE_ANON_KEY` publik. Tanpa keduanya artifact CI berjalan dalam mode lokal.
Artifact CI hanya menyimpan hasil build/coverage, tidak database atau key.
CI Linux belum dianggap lulus sebelum job benar-benar dijalankan di GitHub.

## Backup dan pemulihan

**Backup terenkripsi dan SQLCipher belum diimplementasikan**; persetujuan
dependency keamanan Fase 7 masih diperlukan. Jangan menganggap PIN/biometrik
mengenkripsi database. Android auto-backup dinonaktifkan untuk menghindari salinan
keuangan plaintext yang tidak disengaja. Sinkronisasi bukan backup point-in-time:
penghapusan juga tersinkron.

### CSV (transaksi saja)

1. Buka **Anggaran → tombol printer/Print → Ekspor CSV**.
2. Simpan di folder/drive terenkripsi yang Anda kendalikan.
3. Untuk impor, buat aset yang diperlukan terlebih dahulu, pilih CSV, periksa
   pratinjau/duplikat/baris invalid, lalu konfirmasi.

CSV tidak memuat saldo awal aset, anggaran, jadwal berulang, pengaturan atau sesi
login. Simpan informasi tersebut terpisah bila mengandalkan ekspor CSV. Jangan
membuka CSV keuangan di layanan online tanpa memahami risikonya.

### Salinan database lokal desktop (penuh, plaintext)

Database bernama `ledgy.sqlite`, berada pada application documents directory
yang dikembalikan `path_provider` (biasanya folder Documents; bisa diarahkan
Windows/OneDrive). Lokasi mengikuti pengguna/perangkat, bukan folder build.

1. Tutup Ledgy sepenuhnya agar SQLite melakukan checkpoint dan melepas lock.
2. Salin `ledgy.sqlite` ke media terenkripsi. Jika masih ada `-wal`/`-shm`, simpan
   sebagai satu set; jangan menyalin database yang sedang ditulis. Jangan hapus
   sidecar untuk "memperbaiki" database.
3. Saat restore, tutup Ledgy, backup dahulu database saat ini, lalu pulihkan
   set file konsisten ke lokasi yang sama. Gunakan versi aplikasi yang kompatibel.
4. Salinan mencakup owner/antrean sinkronisasi: gunakan akun cloud pemilik yang
   sama. Sesi login OS tidak termasuk; mungkin perlu login kembali.

Database Android berada di sandbox aplikasi dan tidak dapat diekspor penuh dari
APK rilis melalui `adb pull` biasa. Saat ini tidak ada tombol backup penuh Android;
verifikasi cloud dan ekspor CSV sebelum migrasi/uninstall. Jangan melakukan root
perangkat hanya untuk backup. Uji pemulihan pada salinan aman sebelum menyatakan
backup siap dipakai.

## Status rilis dan pemeriksaan sebelum distribusi

Lihat [catatan Fase 8](docs/PHASE8.md) untuk hasil build aktual dan keterbatasan.
Uji pada perangkat nyata: ikon/splash terang/gelap, signup+konfirmasi, sinkron dua
perangkat, mode offline, biometrik/PIN, izin notifikasi, font besar, dan restore.
Rilis file tidak otomatis berarti siap dipublikasikan ke store.

## Fase 7 — keamanan dan penyempurnaan (sebagian)

Password Ledgy dan biometrik tersedia di Pengaturan, dengan pemeriksaan dukungan
perangkat sebelum aktivasi biometrik, tombol sinkron berupa ikon ringkas, dan
baris pengaturan tanpa blur. Profil penabung dikelola melalui Detail Akun.
Lihat [pengaturan dan keamanan](docs/SETTINGS_SECURITY.md). Penutup konten
saat aplikasi kembali dari latar belakang. Error logging telah diperketat,
area sentuh dan dukungan font besar diperbaiki, dan blur diuji per layar.
Enkripsi database/backup masih menunggu persetujuan dependency; Android fisik
belum tersambung untuk pengukuran performa. Lihat [audit Fase 7](docs/PHASE7.md).

## Fase 6 — login dan sinkronisasi

Login/daftar opsional bergaya glass tersedia melalui **profil → Detail Akun → Daftar / Login**.
Setelah berhasil masuk, lanjutkan mengisi nama aset dan saldo awal.
Status sinkron tersedia melalui **Setting**. Tanpa login, aplikasi tetap lokal.
Detail Akun menyediakan perubahan informasi akun dan **Keluar dari aplikasi**.
Foto ditampilkan jika metadata akun menyediakan `avatar_url`; selain itu memakai avatar bawaan.

Dropdown Ledgy memakai satu panel glass dengan header, garis pemisah, ikon dan
tulisan. Menu membuka ke bawah; Escape, klik luar atau tekan header untuk
menutupnya. Tombol tertutup tidak memakai blur; hanya satu blur pada panel menu
terbuka, daftar pilihan dibuat secara lazy, dan animasi menghormati pengaturan
pengurangan gerakan. Foto profil didekode sesuai kepadatan piksel perangkat.
Sinkronisasi memakai antrean SQLite persisten, timestamp server, soft delete,
retry offline, debounce perubahan, dan tombol manual. Ikuti
[panduan Fase 6](supabase/SYNC.md) untuk migrasi tambahan, URL/anon key, callback
Android, build Windows/Android, serta batasan konflik dan perlindungan akun.

## Fase 5 — backend Supabase

Skema PostgreSQL, RLS, timestamp server, dan index tersedia di
[supabase/migrations/20261001000000_create_ledgy_backend.sql](supabase/migrations/20261001000000_create_ledgy_backend.sql).
Ikuti [panduan setup Supabase dan Auth email](supabase/README.md) untuk membuat
proyek dan menjalankan migrasi. Konfigurasi klien hanya URL dan key publik;
UI login/sinkronisasi Flutter tersedia mulai Fase 6.

## Fase 4 — fitur lanjutan lokal

Akses **Anggaran** di antara Transaksi dan Aset pada sidebar/navigasi bawah.
Pilih **Anggaran Bulanan** atau **Transaksi Berulang** di bagian atas halaman.
Tombol printer kanan bawah (melebar menjadi **Print** saat hover) membuka ekspor/impor CSV.
Tab **Analisis** kini memuat seluruh grafik laporan; tidak ada tombol Laporan terpisah.

- **Anggaran bulanan:** pilih kategori induk dan batas rupiah. Pengeluaran seluruh
  aset dan subkategori dijumlahkan untuk bulan yang dipilih. Tekan **Aktifkan
  notifikasi** dan izinkan notifikasi di Android. Peringatan 80% dan 100% masing-masing
  dikirim sekali per anggaran/bulan; jika langsung melewati 100%, hanya peringatan
  100% yang dikirim. Izin yang ditolak tidak menghabiskan penanda peringatan.
  Anggaran tidak otomatis disalin ke bulan berikutnya.
- **Transaksi berulang:** pemasukan/pengeluaran harian, mingguan, atau bulanan dengan
  interval, aset, kategori, nominal, catatan, dan tanggal/jam mulai. Jadwal terlewat
  dibuat saat aplikasi dibuka/aktif kembali; Android juga mendaftarkan Workmanager
  periodik satu jam tanpa syarat internet. Sistem dapat menunda pekerjaan karena
  penghematan baterai atau force-stop. Desktop hanya memproses saat aplikasi aktif.
  Jadwal dapat dijeda, dilanjutkan, atau dihapus; transaksi yang sudah dibuat tetap ada.
  Tanggal 31 tetap kembali ke 31 setelah bulan pendek. Maksimal 500 tanggal per
  aturan diproses per putaran untuk membatasi beban; sisanya di putaran berikutnya.
  Aset yang diarsipkan tidak menghasilkan transaksi baru.
- **Analisis:** enam bulan sampai bulan pilihan, grafik batang pemasukan/pengeluaran,
  cincin pengeluaran per kategori, dan cashflow bulanan. Transfer antar-aset tidak
  dihitung sebagai pendapatan/beban. Semua bulan memakai zona waktu lokal.
- **CSV:** ekspor seluruh transaksi aktif; impor dengan pratinjau dan konfirmasi.
  Duplikat diperiksa melalui ID atau kombinasi jenis, nominal, aset, tujuan,
  kategori, catatan, dan detik waktu, termasuk transaksi terhapus. Duplikat dalam
  berkas yang sama juga dilewati. Baris tidak valid dilewati secara eksplisit pada
  konfirmasi. Aset harus sudah dibuat; pencocokan melalui ID atau nama unik.
  Kategori baru hanya disimpan saat impor dikonfirmasi. Maksimal 10 MB/10.000 baris.
  CSV berisi data keuangan pribadi; simpan di lokasi aman. CSV bukan backup saldo
  awal, anggaran, atau jadwal berulang.

Format CSV UTF-8 (BOM diperbolehkan), pemisah koma atau titik-koma, nominal rupiah
bulat tanpa pemisah ribuan, jenis `income`, `expense`, atau `transfer`, tanggal
ISO-8601 dengan zona waktu (`2026-10-01T15:30:00Z` = 22.30 WIB).
Kolom ekspor:

```text
id,type,amount,account_id,account_name,to_account_id,to_account_name,category_id,category_name,note,occurred_at
```

Impor memerlukan `type`, `amount`, `occurred_at`, dan ID/nama aset;
pengeluaran/pemasukan memerlukan ID/nama kategori. Transfer memerlukan ID/nama
aset tujuan yang berbeda. Nama subkategori ditulis `Makan & Minum • Cafe / Warkop`.
Teks ekspor dilindungi dari formula spreadsheet, kutip/koma/baris baru di-escape.
Impor memvalidasi ulang di dalam transaksi database saat konfirmasi agar pratinjau
yang sudah kedaluwarsa tidak membuat duplikat. Tabel penanda lokal dibuat tanpa
menimpa data transaksi yang sudah ada.

Validasi dan build dari folder yang berisi `pubspec.yaml`:

```powershell
flutter analyze
flutter test
flutter build windows --release --no-tree-shake-icons
flutter build apk --release
```

Build Windows menyertakan font ikon lengkap melalui `--no-tree-shake-icons` agar
ikon baru tetap tersedia pada build berikutnya. Setelah build, jalankan
`node tool/verify_windows_icons.mjs` untuk memeriksa semua ikon Material yang
digunakan aplikasi terhadap font di bundle Windows. CI menjalankan pemeriksaan ini.

Notifikasi Windows menggunakan identitas aplikasi `com.ledgy.ledgy`; pastikan
notifikasi Ledgy diizinkan dalam pengaturan Windows. Pengiriman toast dan jadwal
Android perlu uji langsung pada perangkat (termasuk pengaturan baterai).

