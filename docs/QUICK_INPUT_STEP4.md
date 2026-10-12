# Quick input — langkah 4

Implementasi hanya di salinan `ledgy-2.0`. Jalur parsing Tier 0 tetap lokal;
tidak ada LLM, klien jaringan, konfigurasi layanan AI, atau dependency baru.

## Batas antarmuka

`domain/parser/draft_parser.dart` mendefinisikan `DraftParser` dengan
`Future<List<TransactionDraft>> parse(String text, ParserContext ctx)`.
`FallbackParser` merupakan antarmuka turunan untuk titik sambung di masa depan,
tanpa implementasi transport apa pun.

`RuleBasedParser` membungkus `parseMany` dari parser Dart langkah 2. API lama
`parse` dan `parseMany` tetap tersedia bagi pengujian domain. UI tidak mengimpor
atau memanggil kedua fungsi tersebut maupun `RuleBasedParser` secara langsung.

`ParserPipeline` memakai rules sebagai tahap pertama. Konfigurasi bawaan dan
`parserPipelineProvider` memakai **aiFallbackEnabled = false** dan
**fallbackParser = null**. Penyiapan fallback tidak membuat atau memanggil klien
jaringan. Pemanggilan slot hanya mungkin jika ketiga kondisi ini terpenuhi:

- Flag diaktifkan secara eksplisit.
- Implementasi fallback disediakan.
- Setidaknya satu draf memiliki confidence **< 0.6** atau jumlah **null**.

Batas 0.6 tanpa jumlah kosong tidak memicu fallback. Untuk batch, fallback
menerima teks asli dan context satu kali; hasilnya menggantikan satu batch utuh,
bukan ditambahkan sehingga transaksi terduplikasi. Jika fallback di masa depan
gagal atau mengembalikan daftar kosong, draf rules tetap dapat diedit manual.
Pipeline mengembalikan daftar yang tidak dapat diubah.

## Antarmuka

`QuickInputBar` menunggu `parserPipelineProvider.parse` untuk teks maupun hasil
suara setelah normalisasi. Hasil tetap menuju kartu konfirmasi yang sama.
Sesudah await, widget yang sudah ditutup tidak membuka konfirmasi.

`DraftConfirmationSheet` menampilkan **Lengkapi manual** bila confidence di bawah
0.6 atau jumlah kosong. Penanda kolom menggunakan masalah validator dan warning
parser yang sudah ada: garis tepi peringatan dan bantuan inline. Tidak ada dialog
error atau proses AI otomatis. Simpan tetap dikendalikan kelengkapan data dari
validator; confidence rendah sendiri tidak melarang menyimpan data yang lengkap
dan telah diperiksa pengguna.

## Pengujian

`test/domain/parser_pipeline_test.dart` mencakup defaults Tier 0, ambang
confidence, jumlah kosong, slot null, batch, kegagalan fallback, dan adapter
rules. Tes tanpa jaringan memasang fallback uji serta `HttpOverrides` yang
menolak pembuatan klien HTTP; pada flag mati jumlah pemanggilan fallback dan
percobaan pembuatan klien harus sama-sama nol. Guard hanya ada pada tes; fitur
produksi tidak mengimpor transport jaringan.

Tes widget membuktikan bahwa input teks dan suara menggunakan pipeline yang
diinjeksi, serta pesan **Lengkapi manual**, penanda jumlah kosong, dan aktivasi
Simpan setelah jumlah diisi. Pengujian domain yang lama tetap menguji parser
aturan tanpa Flutter di kode produksi.

Log pemeriksaan: `build/quick-input-step4-*.log`.

Hasil pemeriksaan:

- `flutter analyze --no-pub`: tidak ada masalah.
- 49 tes khusus pipeline dan konfirmasi lulus.
- Seluruh 427 tes proyek lulus (16 tes baru pada langkah 4).
- SHA-256 238 berkas sumber dan tiga artefak rilis versi stabil tetap identik
  dengan `BASELINE_COPY.json`.
- Build debug Windows berhasil setelah pengulangan dengan log rinci, tanpa
  perubahan kode tambahan. Executable tetap
  `build/windows/x64/runner/Debug/ledgy_2_0.exe`, identitas **Ledgy 2.0** dan versi
  **2.0.0+1**. Log sukses: `quick-input-step4-windows-build-verbose.log`.
  Tidak ada pemasangan atau peluncuran aplikasi.
