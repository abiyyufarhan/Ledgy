# Formulir transaksi dari prompt

Formulir input cepat memakai permukaan gelap yang sama dengan formulir manual
melalui `TransactionFormSurface`, judul **Transaksi Baru**, kolom standar setinggi
64 piksel pada skala teks normal, pilihan tanggal dengan jam/menit, catatan
multibaris dan tombol **Simpan transaksi**. Ukuran menyesuaikan skala teks.
Peringatan isian tetap tampil di kolom yang perlu diperbaiki.

**Detail input** berada di bawah tombol simpan dan tertutup saat formulir dibuka.
Bagian ini memuat teks asli, tingkat keyakinan, peringatan parser, dan tombol
melihat teks OCR untuk struk. Item struk tetap ditampilkan di bawah catatan.

Transfer ke penerima lain memakai kolom **Nama Penerima** dan **Rekening Penerima**
berdampingan. Keduanya wajib diisi sebelum disimpan. Rekening disimpan sebagai
teks sehingga angka nol awal tetap ada. Transfer antar akun sendiri yang sudah
dikenali parser tetap memakai akun tujuan. Pilihan untuk beralih antara transfer
antar akun sendiri dan penerima lain tersedia dalam **Detail input**.

`TransactionDraft` menyertakan `recipientName` dan `recipientAccount` serta
`copyWith` yang mendukung pengosongan keduanya. Validator memeriksa penerima
untuk transfer eksternal dan tetap menolak akun asal/tujuan yang sama untuk
transfer internal. **Edit manual** membawa data penerima beserta jumlah,
tanggal, akun, kategori dan catatan yang telah diedit.

Penyimpanan tetap melalui `QuickInputActions` dan repository transaksi yang
sudah ada. Kategori serta pembelajaran lokal disimpan secara atomik. Tidak ada
perubahan skema database atau konfigurasi cloud.

Pratinjau UI tersedia di `build/ui-previews/prompt-transfer-390.png` dan
`build/ui-previews/prompt-transfer-1280.png`.

Build Windows `2.0.0+4` ditempatkan di
`build/windows/prompt-form-release-build4/ledgy_2_0.exe` untuk menjaga aplikasi
build sebelumnya yang sedang berjalan. Shortcut induk **Ledgy 2.0.lnk** mengarah
ke build baru. Tutup jendela Ledgy 2.0 lama lalu buka shortcut untuk melihat
perubahannya. APK Android sebelumnya belum dibangun ulang untuk perubahan ini.

Validasi akhir: analisis kode bersih dan seluruh 523 tes lulus (dua proses,
batas waktu dua menit). Pratinjau ponsel dan desktop sudah diperiksa. Installer
build 4 lulus pemasangan, pemasangan ulang dan penghapusan di folder sementara,
35 hash payload, 107 ikon Material dan dependensi 20 binary x64. File uji pengguna
tetap ada setelah penghapusan. Konfigurasi cloud identik dengan konfigurasi
yang telah dimigrasikan; 238 sumber serta tiga berkas distribusi/shortcut
Ledgy 1.0 tetap utuh.
