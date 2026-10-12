# Pemilih kategori input cepat

Konfirmasi transaksi hasil teks, suara, dan struk memakai
`showLedgyCategoryPicker` dan `TransactionPickerField` yang juga digunakan
editor transaksi manual. Daftar dibentuk dari katalog kategori bawaan dan
kategori aktif milik pengguna, sesuai jenis pemasukan atau pengeluaran.
Transfer tidak memiliki kolom kategori.

Pencarian mencakup kategori utama dan subkategori. Hasil pilihan ditampilkan
sebagai `Kategori • Subkategori`. Nama pemasukan lama seperti `Gaji` tetap
memakai ID yang sudah ada, dengan label `Pemasukan • Gaji`.

Kategori yang belum ada dipratinjau di `QuickInputCategories`. Saat menyimpan,
ID kategori yang sudah ada digunakan kembali, atau kategori baru dibuat di
transaksi database yang sama dengan penyimpanan melalui repository transaksi
dan pembelajaran lokal. Bila penyimpanan gagal, seluruh perubahan dibatalkan.
Menutup pemilih tanpa memilih mempertahankan kategori draf sebelumnya.

Pengujian mencakup pencarian dan pemilihan subkategori pada ukuran layar
ponsel/desktop, kategori buatan pengguna, kategori pemasukan lama, pemilih
yang dibatalkan, penggunaan ulang kategori dan pembatalan penyimpanan gagal.

Windows build `2.0.0+3` memakai konfigurasi cloud yang telah dimigrasikan.
File Ledgy versi 1.0 tidak diubah.

Validasi: `flutter analyze` bersih; seluruh 511 tes lulus, termasuk 55 tes
konfirmasi, katalog kategori, dan antarmuka input cepat.

Build Windows release selesai. Installer
`build/releases/Ledgy-2.0-Setup-2.0.0-build3-x64.exe` juga disalin ke folder induk
`Installer Ledgy 2.0`. Shortcut induk `Ledgy 2.0.lnk` mengarah ke executable
release terbaru. Installer lulus uji pemasangan/pemasangan ulang/penghapusan
di folder sementara, 35 hash payload, 107 ikon Material, dan dependensi 20
binary x64. Berkas uji pengguna tetap ada setelah penghapusan installer.

Verifikasi SHA-256 seluruh 238 berkas sumber dan tiga berkas distribusi/shortcut
Ledgy 1.0 tidak menemukan perubahan. Build Android sebelumnya belum dibangun
ulang untuk perubahan kategori ini.
