# Mengunggah Ledgy 2.0 ke GitHub

Repositori lokal berada di folder `ledgy-2.0`. Folder versi lama, installer, dan video di luar folder ini tidak ikut masuk.

## Berkas yang dikecualikan

`.gitignore` mengecualikan konfigurasi cloud lokal, `.env`, kunci penandatanganan Android, private key, direktori `release-private`, database lokal dan backup, hasil build, serta cache alat. Jangan memasukkan password database, `service_role`, secret key backend, token Supabase CLI, atau token GitHub ke source code atau dokumentasi.

Contoh konfigurasi dengan placeholder boleh masuk. Struktur database dan migrasi SQL boleh masuk jika tidak memuat data pengguna atau kredensial. Jangan menambahkan file sensitif menggunakan `git add -f`.

## Unggah pertama

1. Di GitHub, buat repositori baru, misalnya `ledgy-2.0`. Pilih **Private** sebagai awal. Jangan centang pembuatan README, `.gitignore`, atau license karena proyek sudah memiliki berkas awal.
2. Buka PowerShell di folder `ledgy-2.0`.
3. Jalankan pemeriksaan, lalu siapkan commit:

```powershell
./tool/check_github_safety.ps1
git add .
./tool/check_github_safety.ps1
git diff --cached --stat
git commit -m "Initial Ledgy 2.0 source"
```

4. Ganti `USERNAME` dan nama repositori di bawah dengan tujuan yang benar:

```powershell
git remote add origin https://github.com/USERNAME/ledgy-2.0.git
git push -u origin main
```

Jika Git meminta login, gunakan autentikasi GitHub melalui browser/Git Credential Manager. Jangan menaruh token di URL remote. Jika identitas Git belum dikonfigurasi, isi `git config user.name` dan `git config user.email` dengan identitas GitHub yang ingin dipakai sebelum melakukan commit.

## Setelah clone di perangkat lain

Konfigurasi cloud tidak ikut diunduh. Salin `supabase/client-config.example.json` menjadi `supabase/client-config.local.json` lalu isi konfigurasi klien secara lokal. Jangan gunakan kredensial admin untuk aplikasi. Gunakan `tool/build_configured.ps1` untuk build yang memakai konfigurasi cloud lokal. Kunci signing Android perlu dipulihkan secara terpisah jika ingin menerbitkan pembaruan dengan identitas signing yang sama.

## Pemeriksaan berikutnya

Jalankan `tool/check_github_safety.ps1` sebelum setiap commit/push. Pemeriksaan memakai pola kredensial yang dikenal dan tidak menampilkan nilainya; hasil PASS tidak menjamin semua jenis rahasia dapat terdeteksi. Tinjau berkas baru sebelum mengunggah.

`.gitignore` tidak menghapus file yang sudah pernah dilacak oleh Git. Jika kredensial pernah terunggah, segera cabut/ganti kredensial tersebut, lalu bersihkan riwayat Git sesuai [panduan GitHub](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository).
