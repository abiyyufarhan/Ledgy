# Langkah 5 — pemindaian struk Android

Di Beranda Android, tekan kamera pada **Input cepat**. Pilih **Kamera** atau
**Galeri**, letakkan struk rata dan terang, periksa pratinjau, lalu tekan
**Baca struk**. Foto dibetulkan menurut EXIF, dikecilkan hingga sisi terpanjang
maksimal 1600 px, dan diubah menjadi JPEG tanpa metadata sebelum OCR Latin.
Pemrosesan gambar berjalan pada isolate agar antarmuka tetap responsif.
Jika format foto tidak didukung, gunakan JPG atau PNG.

Nama dan harga dari fragmen OCR yang sejajar digabung menjadi satu baris.
Parser Dart membaca total, item, pajak/service/diskon, tanggal, toko, dan metode
bayar. Kategori toko memakai kamus lokal; memori koreksi pengguna diutamakan.
QRIS/debit tidak menebak bank jika tidak ada akun yang cocok. Akun terakhir,
tanggal bawaan, total cadangan, angka yang diperbaiki, dan selisih hitungan
ditandai untuk diperiksa. Total cadangan memakai nilai terbesar di separuh bawah
dan mengabaikan uang tunai, kembalian, nomor telepon, dan tanggal.

Hasil selalu dibuka sebagai **Konfirmasi transaksi**, dengan item hanya baca dan
**Lihat teks OCR**. Periksa jumlah, akun, kategori dan tanggal. Validator tetap
menonaktifkan Simpan saat isian wajib bermasalah. Buang, menutup konfirmasi, atau
membatalkan editor manual melepaskan foto sementara. Semua transaksi disimpan
melalui `TransactionActions` dan `TransactionsRepository` yang sudah ada.

## Privasi dan lampiran

OCR menggunakan dependensi native **bundled**
`com.google.mlkit:text-recognition:16.0.1` dari plugin
`google_mlkit_text_recognition` 0.17.1, bukan model yang perlu diunduh melalui
Google Play. Fitur ini tidak menyediakan API upload gambar atau OCR teks.
Sinkronisasi ledger yang sudah ada tetap terpisah dari pemindaian.

Pengaturan **Simpan foto struk sebagai lampiran** bawaan **mati**. Jika aktif,
Simpan menyalin JPEG yang sudah diproses ke folder privat `ledgy_2_0/receipts`
dan menautkannya ke UUID transaksi dalam `ledgy_local_state`. Tautan, foto, dan
teks OCR tidak masuk payload sinkronisasi. Gagal menyimpan membatalkan tautan
dan menghapus salinan yang disiapkan. Transaksi dengan lampiran menampilkan
**Lihat foto struk** pada daftar transaksi Android. Reset data/penghapusan akun
juga membersihkan lampiran lokal; mematikan preferensi hanya menghentikan
penyimpanan foto berikutnya.

File sementara milik aplikasi dibersihkan setelah alur selesai atau halaman
ditutup. Foto asli pengguna di galeri tidak dihapus. Saat Android menghentikan
aktivitas pemilih gambar, Beranda mencoba `retrieveLostData` untuk memulihkan
pilihan, sekaligus membersihkan foto pratinjau dari proses sebelumnya.
Pemulihan hanya dicoba satu kali per sesi agar foto yang sudah dibuang tidak
dibuka lagi saat kembali ke Beranda. File kamera yang tidak dikembalikan oleh
pemilih saat pengguna membatalkan pengambilan juga dibersihkan; snapshot hanya
menargetkan file JPG kamera baru milik aplikasi, bukan foto galeri pengguna.
Izin yang ditolak ditampilkan sebagai bantuan di halaman, dengan tautan ke
pengaturan sistem. Tidak diperlukan izin membaca seluruh penyimpanan galeri.

## Platform dan build

Kamera dan pengaturan struk hanya muncul pada Android. Pada desktop/input cepat
ditampilkan **Pemindaian struk tersedia di Android**. Input teks dan suara yang
sebelumnya didukung tetap tersedia.

Android 2.0 memakai `applicationId=com.ledgy.ledgy2`, label **Ledgy 2.0**, database
`ledgy_2_0`, serta callback `com.ledgy.ledgy2://auth/callback`, sehingga tidak
mengganti instalasi/data Ledgy lama. Jika memakai cloud, tambahkan callback 2.0
pada daftar URL yang diizinkan di proyek backend khusus pengujian 2.0.
Minimum Android adalah SDK 23 atau minimum Flutter yang lebih tinggi.

Build untuk uji lokal dari folder `ledgy-2.0`:

```powershell
D:\flutter-sdk\bin\flutter.bat build apk --debug
D:\flutter-sdk\bin\flutter.bat build windows --debug
```

APK debug: `build/app/outputs/flutter-apk/app-debug.apk`. Windows:
`build/windows/x64/runner/Debug/ledgy_2_0.exe`, dengan DLL dan folder data tetap
berdampingan. APK debug menyediakan layar debug; bukan paket rilis distribusi.
Jangan menjalankan skrip installer versi stabil untuk membungkus salinan 2.0.

## Fixture dan pengujian

Pengaturan Android **Debug OCR struk** hanya tersedia pada debug build. Pilih
foto, **Baca struk**, lalu **Ekspor OcrLine ke JSON**. Ekspor berisi daftar
`{text,left,top,right,bottom}` asli sebelum penggabungan. Tidak ada ekspor
otomatis atau penulisan OCR ke log. File JSON bisa berisi informasi pribadi;
gunakan struk uji tanpa informasi pribadi saat menambah fixture repository.

Delapan fixture awal di `test/fixtures/receipts/` semuanya **sintetis**:
minimarket, restoran dengan PPN/service, SPBU, apotek, diskon panjang, total
terpotong, OCR buram, dan fragmen miring. Belum ada foto struk nyata yang
diberikan. Tambahkan hasil ekspor perangkat nyata sebagai fixture baru dan
nilai yang diharapkan di `test/domain/receipt_parser_test.dart`.

Test meliputi penggabungan geometri, total/item, tanggal dan koreksi OCR,
prioritas memori, akun pembayaran, batas selisih 1%, EXIF/resolusi, rollback
lampiran, kamera/galeri palsu, konfirmasi/Buang, hasil OCR kosong, platform,
debug, serta font 200%. Test widget memakai backend palsu; kualitas kamera dan
akurasi ML Kit pada perangkat Android nyata belum diverifikasi di mesin ini.

Referensi: [ML Kit Android](https://developers.google.com/ml-kit/vision/text-recognition/v2/android),
[plugin OCR](https://pub.dev/packages/google_mlkit_text_recognition),
[image_picker](https://pub.dev/packages/image_picker). Pustaka `image` dipatok
4.3.0 agar tetap kompatibel dengan dependensi `archive` dari ekspor Excel yang
sudah ada.

## Hasil verifikasi 9 Oktober 2026

- Seluruh 478 tes lulus (`build/receipt-complete-tests.log`).
- Analisis Flutter bersih (`build/receipt-verified-analyze.log`).
- APK debug terbaru berhasil dibangun (`build/receipt-android-verified-build.log`).
  Metadata APK diperiksa: paket `com.ledgy.ledgy2`, label `Ledgy 2.0`, versi `2.0.0`.
- Build debug Windows terbaru berhasil (`build/receipt-windows-verified-build.log`).
- SHA-256 dari 238 berkas sumber stabil serta tiga berkas release/shortcut
  cocok dengan `BASELINE_COPY.json`; tidak ada perubahan versi stabil.
- Belum diuji dengan kamera atau OCR pada perangkat Android nyata.

Pada mesin pengembangan ini linker MSVC 14.51 mengalami crash. Build Windows
berhasil memakai MSVC 14.52.36725, dengan jalur header/library ATL dari instalasi
14.51.36231 yang sudah tersedia. Penyesuaian hanya berada pada cache CMake di
`build/windows/x64`, tanpa mengubah instalasi SDK global atau proyek stabil.
Peringatan compiler berasal dari plugin native; build selesai tanpa error.
