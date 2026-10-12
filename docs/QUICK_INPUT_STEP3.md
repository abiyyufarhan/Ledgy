# Quick input — langkah 3

Implementasi berada di salinan `ledgy-2.0` dan memakai parser/kartu konfirmasi
dari langkah 1–2. Dependency sesuai permintaan: `speech_to_text` 7.5.0 dan
`permission_handler` 12.0.3 (versi hasil lockfile).

## Penggunaan

Pada Beranda mobile, panel glass **Input cepat** menampilkan kolom ketik,
mikrofon, kamera, dan tombol tinjau. Tekan Enter/Done atau tombol panah untuk
membuka kartu konfirmasi. Pada desktop, klik **Input cepat · Ctrl+K** atau tekan
Ctrl+K saat berada di Beranda. Command bar otomatis memfokuskan kolom ketik;
Escape atau tombol tutup menutupnya.

Contoh teks/ucapan:

- `makan siang tiga puluh lima ribu rupiah pakai go pay`
- `bensin lima puluh ribu`
- `gaji delapan juta masuk ke b c a`
- `kopi 20rb via GoPay; bensin 50rb via Tunai`

Kamera merupakan tombol nonaktif dengan petunjuk bahwa pemindaian struk
dihubungkan pada langkah 5; belum ada akses kamera atau permintaan izinnya.

## Alur konfirmasi

`QuickInputBar` membaca `parserContextProvider`, lalu memakai `parseMany` agar
seluruh draf dipertahankan. Satu draf langsung membuka `DraftConfirmationSheet`.
Beberapa draf menjadi daftar kartu; pilih **Tinjau & simpan** pada setiap kartu.
Kartu selesai ditandai **Tersimpan** atau **Dibuang**. Tidak ada simpan semua atau
penyimpanan otomatis. Buang draf tersisa mengosongkan antrean tanpa menghapus
transaksi yang sudah disimpan.

Simpan tetap melewati `QuickInputActions` → `TransactionActions` → repository
transaksi yang ada, beserta pembelajaran koreksi lokal. Hasil simpan dari Edit
manual diteruskan kembali lewat `onDraftSaved`, sehingga kartu yang sudah
tersimpan tidak menawarkan simpan ulang. Menutup editor tanpa menyimpan
mempertahankan draf yang dapat ditinjau lagi.

Kolom/tombol dilindungi selama parsing, perekaman, dan konfirmasi. Indikator
memuat hanya aktif saat menyiapkan context. Error context tampil inline dan
bisa dicoba lagi, tanpa menampilkan exception/parameter sensitif.

## Input suara

`SpeechVoiceBackend` membungkus layanan native. `VoiceInputController` mengelola
izin, persiapan, mendengarkan, penyelesaian, pembatalan, dan hasil final. Layanan
diinisialisasi hanya setelah pengguna menekan mikrofon dan izin diterima.
Paket bahasa harus melaporkan `id_ID` atau `id-ID`; Ledgy tidak mengganti ucapan
Indonesia ke bahasa Inggris ketika bahasa Indonesia tidak ada.

Izin mikrofon diminta melalui `permission_handler`. Penolakan memberi panduan
Pengaturan sistem. Penolakan permanen/restricted juga menyediakan **Buka
pengaturan**; jika OS/plugin tidak bisa membukanya, petunjuk manual tetap ada.
Nama menu dapat berbeda menurut perangkat dan layanan suara.

Android memakai channel `com.ledgy.ledgy2/speech` untuk memeriksa
`SpeechRecognizer.isOnDeviceRecognitionAvailable` pada Android 12/API 31 ke atas.
Jika tersedia, sesi memakai `SpeechListenOptions.onDevice: true`; jika tidak,
layanan standar perangkat dipakai dan dapat memerlukan internet. Manifest
menambahkan `RECORD_AUDIO` dan query `RecognitionService`. Bluetooth tidak
diminta; inisialisasi memakai opsi `androidNoBluetooth`.

Saat mendengarkan, `RingProgress` berdenyut dan teks sementara diperbarui
langsung. Preferensi kurangi animasi dihormati. Stop menunggu hasil final;
batal membuang ucapan. Hasil final masuk alur konfirmasi dengan `DraftSource.voice`.
`VoiceNormalizer` menyamakan go pay/gopay dan b c a/bca; angka kata dan rupiah
selanjutnya diproses parser Dart yang sudah ada.

Callback sesi lama diabaikan setelah batal, final, background, atau dispose.
Hasil final diproses maksimal sekali per sesi. Teks sementara dibersihkan saat
akhir/batal sesi, dan kartu selesai tidak mempertahankan rawText. Aplikasi tidak
membuat file audio, menyimpan rawText/transkrip lengkap ke database, atau menulis
ucapan ke log. Catatan transaksi hasil parsing/koreksi tetap bagian ledger biasa
dan dapat menghasilkan kata kunci memori lokal sebagaimana langkah 2.

## Dukungan dan batasan platform

Target native yang dikonfigurasi adalah Android dan Windows. Linux menyembunyikan
mikrofon karena tidak memiliki implementasi speech_to_text. Web dan Apple belum
dikonfigurasi di proyek ini, sehingga mikrofon tidak ditampilkan di sana.

Package Windows terpasang (`speech_to_text_windows` 1.0.1) memakai SAPI lokal,
tetapi `GetLocales` hanya melaporkan `en-US`/`en-GB`; `id_ID` belum tersedia dari
implementasi ini. Ledgy menampilkan bantuan bahasa dan mempertahankan input
ketik, tanpa memulai pengenalan dengan bahasa yang salah. Panduan unduh paket
ucapan hanya berlaku jika Windows/layanan menawarkan bahasanya; pemasangan paket
tidak menjamin plugin ini akan melaporkan Indonesia. Plugin permission_handler
Windows tidak memberi dialog izin mikrofon per aplikasi; akses desktop dikelola
di Pengaturan Windows.

Rujukan API resmi:
[speech_to_text](https://pub.dev/packages/speech_to_text),
[SpeechToText.listen](https://pub.dev/documentation/speech_to_text/latest/speech_to_text/SpeechToText/listen.html),
[permission_handler](https://pub.dev/packages/permission_handler).
Batasan Windows diverifikasi pada source package versi yang terkunci.

## Verifikasi

Tes mencakup seluruh kalimat suara yang diminta, normalisasi, izin ditolak/
permanen, locale hilang, on-device, teks sementara, final tunggal, callback lama,
stop/batal, lifecycle, Ctrl+K/Escape, mobile dengan font 200%, repository simpan,
antrean beberapa draf, dan Edit manual. Tes speech memakai backend simulasi;
mikrofon fisik Android perlu dicoba pada perangkat dengan layanan/paket bahasa
Indonesia tersedia.

```powershell
flutter analyze --no-pub
flutter test --no-pub --concurrency=2
```

Log berada di `build/quick-input-step3-*.log`. Sumber, executable, shortcut, dan
installer versi stabil tetap diperiksa terhadap SHA-256 baseline. Tidak ada
pemasangan aplikasi ke perangkat atau perubahan pada instalasi stabil.

Hasil verifikasi langkah 3:

- `flutter analyze --no-pub`: tidak ada masalah.
- Seluruh 411 tes lulus, termasuk 30 tes baru untuk normalisasi suara,
  controller, dan antarmuka input cepat.
- Dua tes Beranda pada lebar 390 dan 1440 lulus; gambar hasil render di
  `build/ui-previews/dashboard-390.png` dan `dashboard-1440.png` diperiksa.
- Build debug Windows berhasil dengan plugin native baru. Executable:
  `build/windows/x64/runner/Debug/ledgy_2_0.exe`, identitas produk **Ledgy 2.0**,
  versi **2.0.0+1**. Build ini untuk mencoba pengembangan, bukan installer rilis.
