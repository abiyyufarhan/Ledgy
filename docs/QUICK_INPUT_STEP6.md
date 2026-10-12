# Langkah 6 — Lab parser dan evaluasi

Perubahan hanya dilakukan di `ledgy-2.0`. Tidak ada LLM atau permintaan jaringan
dari parser, Lab, OCR, maupun ekspor diagnostik. Semua transaksi tetap disimpan
melalui kartu konfirmasi dan repository yang sudah ada.

## Menggunakan Lab

Pada build debug, buka **Pengaturan → Input cepat → Lab parser**. Tempel kalimat
dan tekan **Urai kalimat**. Lab menampilkan normalisasi, pemisahan, tanggal UTC,
akun, nominal, jenis, kategori/catatan, perhitungan confidence, warning validator,
dan durasi parser. Langkah berasal dari aturan yang benar-benar dieksekusi oleh
ParserPipeline, bukan simulasi terpisah. Kartu Lab tidak menyimpan transaksi.
Lab dan pintu masuknya dihilangkan pada build profile/release.

## Catatan kegagalan lokal

**Catat kalimat gagal diurai** bawaan mati. Jika diaktifkan, input ketik di Beranda
dan Lab dicatat ketika confidence < 0,6 atau ada masalah validator, termasuk
nominal/kategori/akun kosong. Kalimat tanpa jumlah tetap dapat ditinjau manual.
Suara dan teks OCR tidak masuk log ini, mengikuti ketentuan privasi langkah 3/5.

Tabel lokal `parser_failures` memiliki satu kolom `text`, tanpa waktu, jumlah,
akun, ID transaksi, confidence, atau payload lain. Teks berulang dideduplikasi;
maksimal 500 kalimat disimpan. Mematikan opsi menghentikan catatan berikutnya.
**Hapus catatan kegagalan** membersihkan log; reset data/hapus akun juga
membersihkannya dan mematikan preferensi. Migrasi schema 3 → 4 mempertahankan
ledger dan menambahkan tabel ini. Tabel tidak masuk daftar sinkronisasi.

**Ekspor kegagalan JSON** tersedia di pengaturan, juga pada Lab debug.
Pemilih file meminta lokasi; JSON hanya berupa array string. Tidak ada ekspor
otomatis. Beri anotasi manual pada teks ekspor sebelum dipakai sebagai golden.

## Korpus dan metrik

`test/fixtures/phrases.csv` berisi 120 kalimat **sintetis** sehari-hari, bukan log
pemakaian nyata. Asal dan aturan anotasi dijelaskan di `test/fixtures/PHRASES.md`.
Clock tetap 8 Oktober 2026 10:00 UTC. Akun Tunai/BCA/GoPay/DANA, tanpa memori.
Tes CSV menghitung akurasi jenis, jumlah, kategori, akun, dan tanggal secara
terpisah serta akurasi nominal hanya pada baris yang memiliki jumlah.

Baseline sebelum perbaikan: jumlah 95,83%, kategori 88,33%, akun 98,33%, jenis
dan tanggal 100%. Terdapat 14 kegagalan kategori, 5 nominal, dan 2 akun.
Perbaikan difokuskan pada kosakata umum makanan/transport/tagihan/hiburan/
kesehatan/pemasukan, format rupiah dengan nol sen, dan ejaan `b c a`.
Baseline tersimpan di `build/parser-corpus-baseline.json`.

Golden menulis `build/parser-corpus-report.json`, termasuk setiap perbedaan,
histogram kegagalan, dan durasi p50/p95/maksimum setelah 20 pemanasan. Batas
regresi nominal minimal 90%; p95 parser di mesin uji di bawah 50 ms. Ini tidak
menjamin semua input/perangkat memiliki waktu yang sama. Golden struk menulis
`build/receipt-corpus-report.json` dan menetapkan total benar minimal 80% dari
delapan fixture OCR sintetis langkah 5; tidak mengukur kualitas OCR foto nyata.

```powershell
& 'D:\flutter-sdk\bin\flutter.bat' test --no-pub test/domain/parser_corpus_golden_test.dart
& 'D:\flutter-sdk\bin\flutter.bat' analyze --no-pub
& 'D:\flutter-sdk\bin\flutter.bat' test --no-pub
& 'D:\flutter-sdk\bin\dart.bat' tool/parser_benchmark.dart
```

Benchmark Dart terpisah melakukan lima putaran pemanasan dan lima putaran
pengukuran (600 sampel), melaporkan p50/p95/maksimum dan mengembalikan exit code
gagal jika ada sampel >= 50 ms. Hasilnya `build/parser-benchmark-report.json`.

## Mengukur di Android nyata

Pada Android debug, buka **Debug OCR struk**, pilih foto, lalu **Baca struk**.
Durasi OCR dan parser ditampilkan terpisah, ditambah total dengan target < 3000 ms.
Stopwatch OCR mencakup recognizer native; stopwatch parser hanya aturan Dart.
Pemilih foto, resize/EXIF, menunggu katalog akun, dan konfirmasi tidak masuk metrik.
Ekspor OcrLine untuk membuat fixture nyata; catat total yang benar dari struk
secara manual, tanpa memakai output parser sebagai jawaban yang diharapkan.

Untuk evaluasi: gunakan HP kelas menengah, catat model/versi OS, siapkan minimal
20 foto struk bervariasi, lakukan pemanasan, kemudian ulangi tiap foto lima kali.
Catat akurasi total, waktu pertama, p50/p95/maksimum, dan urutkan kelompok
kegagalan (total terpotong, baris terpisah, nominal OCR, dll.) sebelum memperbaiki
aturan. Uji offline. Fixture JSON saja tidak mengukur waktu/akurasi ML Kit.

Data kalimat/struk nyata dan perangkat Android belum tersedia pada mesin ini.
Karena itu target akurasi nyata dan OCR < 3 detik belum dapat dinyatakan tercapai.

## Hasil verifikasi 9 Oktober 2026

Seluruh 501 tes lulus; 40 tes terarah dijalankan lagi setelah penyesuaian terakhir
pada privasi dan lifecycle provider, semuanya lulus. Analisis Flutter bersih.

| Metrik | Baseline | Setelah perbaikan |
| --- | ---: | ---: |
| Jenis (120 kalimat sintetis) | 100% | 100% |
| Jumlah (termasuk 6 tanpa nominal) | 95,83% | 100% |
| Kategori | 88,33% | 100% |
| Akun | 98,33% | 100% |
| Tanggal kalender | 100% | 100% |
| Total struk (8 fixture sintetis) | 100% | 100% |

Benchmark Dart VM Windows terpisah (600 sampel setelah pemanasan): p50 0,266 ms,
p95 0,537 ms, maksimum 2,158 ms. Tidak ada sampel mencapai 50 ms.
Angka ini mengukur korpus pengembangan sintetis, bukan akurasi pada data nyata
yang belum pernah dipakai untuk perbaikan atau kinerja OCR Android.

Log verifikasi: `build/parser-step6-all-tests.log`,
`build/parser-step6-final-targeted-tests.log`, `build/parser-step6-verified-analyze.log`,
dan `build/parser-step6-benchmark.log`.

Build debug Windows dan Android terbaru berhasil; log berada di
`build/parser-step6-windows-build.log` dan `build/parser-step6-android-build.log`.
Executable Windows: `build/windows/x64/runner/Debug/ledgy_2_0.exe` (pertahankan
DLL dan folder `data` di sebelahnya). APK: `build/app/outputs/flutter-apk/app-debug.apk`.
Paket Android tetap `com.ledgy.ledgy2`, label Ledgy 2.0. Tutup dan buka ulang
aplikasi 2.0 bila versi sebelumnya masih berjalan. Tidak ada pemasangan atau
peluncuran aplikasi otomatis dari proses verifikasi ini.

Pemeriksaan SHA-256 memastikan 238 berkas sumber serta tiga berkas release/
shortcut versi stabil identik dengan baseline. Ringkasan artefak dan metrik:
`build/parser-step6-validation.json`.
