# Fase 5 — backend Supabase Ledgy

Migrasi berada di [migrations/20261001000000_create_ledgy_backend.sql](migrations/20261001000000_create_ledgy_backend.sql).
Fase ini menyiapkan database dan panduan Auth. Login opsional dan sinkronisasi
Flutter sekarang tersedia: lanjutkan dengan [panduan Fase 6](SYNC.md), termasuk
migrasi tambahan `20261002000000_sync_window.sql`.

## 1. Membuat proyek

1. Masuk ke [Supabase Dashboard](https://supabase.com/dashboard).
2. Pilih **New project**, organisasi, nama misalnya **Ledgy**, region, dan password
   database. Simpan password database di pengelola password.
3. Tunggu proyek siap. Catat project reference dari URL Dashboard
   (`/project/<project-ref>`) dan Project URL dari dialog **Connect**.
4. Di **Settings → API Keys**, ambil key publik **anon** dari bagian legacy keys,
   sesuai konfigurasi fase ini. URL dan anon key adalah konfigurasi klien;
   autentikasi pengguna dan RLS yang membatasi baris.

Supabase kini juga menyediakan **publishable key** (`sb_publishable_...`) sebagai
pengganti anon. Jika Dashboard menampilkan key baru, gunakan hanya key publik
tersebut ketika integrasi klien disiapkan. Jangan memakai **service_role**,
**secret key** (`sb_secret_...`), password database, atau access token CLI di APK,
EXE, kode Flutter, maupun konfigurasi klien. Key berprivilege dapat melewati RLS.
[Referensi API keys](https://supabase.com/docs/guides/getting-started/api-keys).

## 2. Menjalankan migrasi

Jalankan dari folder Flutter `ledgy`, yang berisi `pubspec.yaml` dan `supabase/`.
Gunakan proyek Supabase baru/kosong; migrasi ini membuat lima tabel baru.

### Melalui CLI

Instal CLI mengikuti [panduan resmi](https://supabase.com/docs/guides/local-development/cli/getting-started).
Jika Scoop sudah tersedia di Windows, tambahkan bucket resmi lalu instal CLI:

```powershell
scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
scoop install supabase
```

Lewati penambahan bucket jika sudah terdaftar.
[Instruksi instalasi Windows](https://github.com/supabase/cli#installation).
Setelah CLI tersedia, jalankan:

```powershell
Set-Location -LiteralPath 'D:\7. PROYEK\6. LEDGY\ledgy'
supabase init
supabase login
supabase link --project-ref PROJECT_REF_ANDA
supabase db push --dry-run
supabase db push
supabase migration list
```

`supabase init` cukup sekali untuk membuat `supabase/config.toml`; file migrasi
yang sudah ada tetap dipakai. Jika config sudah ada, lewati init.
Masukkan password database ketika CLI memintanya. CLI login digunakan oleh
alat pengembangan, bukan sebagai kredensial aplikasi.

`db push --dry-run` memperlihatkan migrasi yang akan diterapkan; `db push`
mencatat migrasi yang sukses dan melewatinya pada push berikutnya.
Untuk proyek yang sudah punya tabel Ledgy, sesuaikan riwayat/skema dahulu,
jangan menimpa tabel yang ada atau menjalankan reset remote.
[Referensi migrasi](https://supabase.com/docs/guides/local-development/database-migrations).

### Melalui SQL Editor (alternatif tanpa CLI)

Buka **SQL Editor → New query**, tempel seluruh isi file migrasi, lalu **Run**.
Jalankan hanya sekali pada proyek kosong. Jangan menjalankan SQL Editor dan
CLI untuk migrasi yang sama tanpa menyelaraskan riwayat. Jika kelak memakai CLI
setelah SQL Editor, tandai versi ini sebagai sudah diterapkan setelah memastikan
skema cocok:

```powershell
supabase migration repair 20261001000000 --status applied
supabase migration list
```

Ini hanya memperbarui riwayat, bukan menjalankan SQL kembali.
[Referensi CLI](https://supabase.com/docs/reference/cli/supabase-migration-repair).

## 3. Mengaktifkan Auth email

1. Buka **Authentication → Sign In / Providers → Email** (pada tampilan lain,
   **Authentication → Providers → Email**).
2. Pastikan provider Email dan pendaftaran pengguna aktif. Aktifkan **Confirm
   email** bila pengguna wajib memverifikasi alamat sebelum login.
3. Di **Authentication → URL Configuration**, isi Site URL dan Redirect URLs
   sesuai halaman/callback yang benar-benar akan menangani konfirmasi dan
   reset password. Android Fase 6 menggunakan `com.ledgy.ledgy://auth/callback`;
   desktop melakukan konfirmasi email lalu masuk manual. Lihat [Fase 6](SYNC.md).
4. Atur **Custom SMTP** untuk pengiriman email ke pengguna umum. SMTP bawaan
   Supabase dibatasi dan ditujukan untuk pengujian; penerima nonanggota tim
   proyek dapat ditolak.
5. Uji signup, konfirmasi email, lalu login melalui klien pengujian. Periksa
   **Authentication → Users**. Sesudah login, request membawa JWT pengguna,
   sehingga `auth.uid()` berisi ID pengguna dan policy kepemilikan berlaku.

Provider email biasanya sudah aktif secara default pada proyek hosted.
SQL migrasi tidak mengubah pengaturan Auth Dashboard.
[Auth email/password](https://supabase.com/docs/guides/auth/passwords),
[Redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls),
[SMTP](https://supabase.com/docs/guides/auth/auth-smtp).

## 4. Konfigurasi klien

[client-config.example.json](client-config.example.json) hanya berisi dua
placeholder: `SUPABASE_URL` dan `SUPABASE_ANON_KEY`. Salin menjadi
`supabase/client-config.local.json` dan ganti nilainya. File lokal diabaikan Git.

Integrasi Flutter Fase 6 membaca konfigurasi dengan `String.fromEnvironment`
yang diberikan saat build:

```powershell
flutter run -d windows --dart-define-from-file=supabase/client-config.local.json
flutter build apk --release --dart-define-from-file=supabase/client-config.local.json
```

Perintah ini mengaktifkan klien Supabase setelah placeholder diganti dan kedua
migrasi diterapkan. Anon key tidak menggantikan login pengguna.
Tanpa sesi pengguna, role `anon` tidak memperoleh akses kelima tabel.
[API keys dan role](https://supabase.com/docs/guides/getting-started/api-keys).

## 5. Skema dan sinkronisasi

- Tabel: `accounts`, `categories`, `transactions`, `budgets`, `recurring_rules`.
  Setiap tabel memiliki UUID `id`, `user_id default auth.uid()`, `created_at`,
  `updated_at`, `deleted_at`, dan `is_dirty` untuk kompatibilitas skema lokal.
- Rupiah disimpan sebagai `bigint`; waktu sebagai `timestamptz`. `month_start`
  menyimpan instan awal bulan lokal yang dikonversi UTC, bukan wajib tanggal
  pertama menurut kalender UTC.
- Transfer tetap satu baris dengan aset asal dan tujuan berbeda. Jenis
  transaksi, nominal, jenis kategori, frekuensi, dan interval diperiksa di DB.
- Semua tabel mengaktifkan RLS dengan empat policy terpisah untuk
  `authenticated`. UPDATE memeriksa pemilik sebelum **dan** sesudah perubahan,
  sehingga pengguna tidak dapat memindahkan kepemilikan. Relasi gabungan
  `(user_id, account_id/category_id)` melarang referensi lintas pengguna.
  [Referensi RLS](https://supabase.com/docs/guides/database/postgres/row-level-security).
- Trigger BEFORE INSERT/UPDATE selalu mengisi `updated_at = now()` dari server,
  termasuk upsert dan perubahan `deleted_at`. Nilai `updated_at` dari perangkat
  tidak dipercaya. Simpan nilai yang dikembalikan server setelah push.
- Index `(user_id, updated_at)` ada di setiap tabel, termasuk baris terhapus.
  `is_dirty` merupakan metadata kompatibilitas, bukan cursor sinkronisasi server.
  `ledgy_local_state` (penanda notifikasi/jadwal perangkat) tidak disalin ke cloud.
- Policy SELECT tetap mengizinkan pemilik membaca tombstone. Daftar UI menyaring
  `deleted_at is null`, tetapi sinkronisasi harus menarik juga baris soft delete.
  Hard delete tidak meninggalkan tombstone; aplikasi sebaiknya menggunakan
  soft delete. Hard delete aset/kategori yang masih dirujuk ditolak oleh FK.
- Upload aset dan kategori sebelum transaksi, anggaran, dan aturan berulang.
  Pertahankan UUID lokal; tidak ada seed bersama yang harus diunggah ke tiap akun.
  Timestamp yang sama dapat terjadi dalam satu transaksi server, jadi cursor
  timestamp saja tidak cukup untuk pagination; implementasi Fase 6 menggunakan
  keyset `(updated_at, id)`, batas server, dan overlap cursor.

## 6. Verifikasi

Di **Database → Tables / Policies**, pastikan ada lima tabel dan masing-masing
memiliki RLS serta empat policy. SQL Editor biasa berjalan dengan hak admin,
jadi membaca semua baris di sana bukan bukti RLS gagal.

Validasi lokal memakai PostgreSQL terisolasi dalam memori melalui PGlite dengan
schema Auth minimal, tanpa menghubungi proyek cloud. Alat ini hanya untuk
pengujian dan tidak menjadi dependency Flutter:

```powershell
npm install --prefix .dart_tool/phase5_validation --no-save --ignore-scripts @electric-sql/pglite
node supabase/tests/verify_schema.mjs
flutter analyze
flutter test
```

Pengujian mencakup lima tabel, default pemilik, timestamp server yang tidak bisa
dipalsukan, SELECT/INSERT/UPDATE/DELETE milik sendiri dan penolakan lintas pengguna,
akses anon, relasi lintas pengguna, tombstone, constraint, dan index.
PGlite memvalidasi SQL dan policy DB; pengaturan GoTrue/email di proyek hosted
tetap diperiksa setelah proyek dan migrasi dibuat.
