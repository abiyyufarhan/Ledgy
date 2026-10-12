# Menjalankan Ledgy 2.0 tanpa mengganggu versi stabil

Versi stabil berada di folder `ledgy` dan tetap dijalankan lewat shortcut atau
installer lama. Versi 2.0 berada di folder `ledgy-2.0`.

Untuk pemakaian harian dengan cloud versi 1.0, gunakan build release
`build/windows/x64/runner/Release/ledgy_2_0.exe` atau installer
`build/releases/Ledgy-2.0-Setup-2.0.0-build5-x64.exe`. Panduan konfigurasi,
login akun lama, pembaruan Android debug, dan dampak sinkronisasi ada di
[MIGRASI_KONFIGURASI_1_0.md](MIGRASI_KONFIGURASI_1_0.md).
File/program versi 1.0 tetap terpisah; kedua versi sekarang memakai proyek cloud
yang sama sehingga perubahan akun yang disinkronkan dapat terlihat di keduanya.

Build debug langkah 6 dengan kategori kopi otomatis dan Lab parser sudah tersedia. Untuk
mencobanya tanpa build ulang, buka
`D:\7. PROYEK\6. LEDGY\ledgy-2.0\build\windows\dashboard-inline\ledgy_2_0.exe`.
Biarkan executable bersama seluruh DLL dan folder `data` di lokasi tersebut.
Hasil terbaru ditempatkan di folder terpisah karena aplikasi dari lokasi debug
sebelumnya sedang berjalan saat build. Untuk melihat perubahan, tutup jendela
Ledgy 2.0 sebelumnya lalu buka executable terbaru di atas.

Untuk Lab parser debug, buka **Pengaturan → Input cepat → Lab parser**.
Tempel kalimat dan tekan **Urai kalimat** untuk melihat hasil, confidence,
warning, urutan aturan, dan durasi. Pengaturan **Catat kalimat gagal diurai**
bawaan mati; ekspor JSON tersedia di bagian yang sama. Panduan dan hasil
pengukuran: [QUICK_INPUT_STEP6.md](QUICK_INPUT_STEP6.md).

Di Beranda, kolom **Ketik transaksi** langsung tampil. Ketik kalimat lalu tekan
Enter atau tombol panah untuk meninjau draf. **Ctrl+K** di desktop mengarahkan
kursor ke kolom ini. Beberapa transaksi ditinjau dan disimpan satu per satu.
Pada konfirmasi, kolom **Kategori** membuka pemilih yang sama dengan transaksi
manual: ikon berwarna, pencarian, kategori utama dan subkategori. Pilihan kategori
pemasukan mengikuti jenis **Masuk**. Kategori buatan pengguna juga ikut tampil.
Kategori baru disimpan bersama transaksi saat menekan **Simpan**; membuang draf
tidak menambahkan kategori ke database.
Formulir prompt kini memakai tampilan **Transaksi Baru** seperti transaksi
manual, termasuk kolom nama dan rekening penerima untuk transfer eksternal.
Teks asli dan tingkat keyakinan dapat dibuka melalui **Detail input**.
Panduan: [QUICK_INPUT_FORM_UI.md](QUICK_INPUT_FORM_UI.md).
Pemindaian struk langkah 5 hanya tersedia di Android. Plugin suara Windows saat ini belum
menyediakan `id_ID`; gunakan input ketik. Dukungan suara Android dan batasan
platform dijelaskan di `QUICK_INPUT_STEP3.md`.

Di Android, tekan kamera pada Input cepat, pilih Kamera/Galeri, lalu Baca struk.
Periksa hasil sebelum Simpan. Foto sementara dihapus setelah selesai;
pengaturan menyimpan foto sebagai lampiran bawaan mati. APK debug berada di
`build/app/outputs/flutter-apk/app-debug.apk` sudah dibangun. Identitas Android
`com.ledgy.ledgy2` dan database `ledgy_2_0` terpisah dari versi stabil.
Rincian dan penggunaan layar debug: [QUICK_INPUT_STEP5.md](QUICK_INPUT_STEP5.md).

Parsing input cepat memakai pipeline lokal langkah 4. Fallback AI tetap
nonaktif dan tidak memiliki implementasi; tidak ada permintaan jaringan dari
pipeline. Draf berkeyakinan rendah menampilkan **Lengkapi manual**.

Coba `minum kopi 35rb pakai Tunai`: kartu konfirmasi langsung memilih
**Makan & Minum • Cafe / Warkop**. Tanpa jumlah, kategori tetap dipilih, tetapi
jumlah harus diisi sebelum Simpan. Rincian: `QUICK_INPUT_CATEGORIES.md`.

Untuk Windows desktop, buka PowerShell lalu jalankan:

```powershell
Set-Location 'D:\7. PROYEK\6. LEDGY\ledgy-2.0'
& 'D:\flutter-sdk\bin\flutter.bat' pub get
& 'D:\flutter-sdk\bin\flutter.bat' devices
& 'D:\flutter-sdk\bin\flutter.bat' --no-version-check run -d windows --dart-define-from-file=supabase/client-config.local.json
```

Setelah `pub get` pertama, jalankan `flutter run` dengan parameter konfigurasi
cloud seperti di atas. Tanpa parameter itu, login cloud dinonaktifkan.
Jendela akan berjudul `Ledgy 2.0` dan proses debug memakai executable
`ledgy_2_0.exe`. Hentikan mode debug dengan `q` di terminal atau tutup jendela.

Data Ledgy 2.0 disimpan pada database Drift bernama `ledgy_2_0`, terpisah dari
database stabil yang bernama `ledgy`. Akun, transaksi, memori quick input, dan
pengaturan lokal tidak dibaca atau ditulis silang oleh kedua versi.

Perintah diagnostik yang tidak membuka aplikasi:

```powershell
& 'D:\flutter-sdk\bin\flutter.bat' analyze --no-pub
& 'D:\flutter-sdk\bin\flutter.bat' test --no-pub
```

Perintah `flutter run` menjalankan salinan pengembangan langsung dan tidak
membuat installer. Installer 2.0 memakai identitas, folder, dan shortcut terpisah.

Judul Beranda, Transaksi, Anggaran, Kelola Aset, Pengaturan, dan halaman
pendukung memakai gaya judul yang sama: Manrope 24, tebal 700, mengikuti
sambutan Beranda. Judul Transaksi Baru pada input manual dan prompt juga seragam.

