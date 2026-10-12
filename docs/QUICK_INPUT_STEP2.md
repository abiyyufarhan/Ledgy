# Quick input — langkah 2

Implementasi hanya berada di salinan `ledgy-2.0`. Modul
`lib/features/quick_input/domain/parser/` memakai Dart murni, tanpa Flutter,
Riverpod, atau Drift. Tidak ada dependency parser tambahan.

## API

```dart
import 'package:ledgy/features/quick_input/domain/parser/transaction_parser.dart';
import 'package:ledgy/features/quick_input/domain/transaction_draft.dart';

final ctx = ParserContext(
  clock: FixedClock(DateTime(2026, 10, 8, 10)),
  accounts: [
    ParserAccount(id: 'tunai', name: 'Tunai', aliases: ['cash']),
    ParserAccount(id: 'bca', name: 'BCA', aliases: ['bank bca']),
    ParserAccount(id: 'gopay', name: 'GoPay', aliases: ['go pay']),
    ParserAccount(id: 'dana', name: 'DANA'),
  ],
  categories: [
    ParserCategory(id: 'makanan', name: 'Makanan', type: TransactionType.expense),
    ParserCategory(id: 'gaji', name: 'Gaji', type: TransactionType.income),
  ],
  lastAccountId: 'tunai',
);
final draft = parse('Beli kopi dua puluh lima ribu via BCA kemarin', ctx);
// amount: 25000; accountId: bca; categoryId: makanan; note: beli kopi.

final drafts = parseMany('kopi 20rb via BCA; gaji 2,5jt via DANA', ctx);
// Dua draf terpisah, tidak ada penyimpanan otomatis.
```

`parse(String, ParserContext)` mengembalikan satu `TransactionDraft` sesuai
titik masuk yang diminta. Gunakan `parseMany` untuk mengambil seluruh transaksi
dalam kalimat. Jika `parse` menerima beberapa transaksi, ia mengembalikan draf
pertama dengan warning `MULTIPLE_TRANSACTIONS` dan teks asli lengkap.
Pemisahan hanya dilakukan bila setiap potongan memiliki jumlah; selain itu
hasilnya satu draf dengan `INCOMPLETE_SPLIT`. Koma desimal/ribuan tidak menjadi
pemisah transaksi. Kata pemisah `dan` tidak peka huruf besar/kecil.

`ParserContext` menyimpan snapshot akun, alias, kategori, memori kata kunci,
Clock, dan ID akun terakhir. Semua daftar tidak bisa diubah. Provider
`parserContextProvider` menyiapkan context dari repository aplikasi; nama akun
berasal dari data akun yang ada. Alias tambahan dapat diberikan lewat
`ParserAccount.aliases` oleh pemanggil. Belum ada halaman pengelolaan alias.

## Aturan parser

- Normalizer mengubah huruf kecil, merapikan spasi, menyamakan `go pay` dengan
  `gopay`, dan mengganti `rp.`, `rp`, atau `rupiah` dengan token internal `¤`.
  `gojek` tetap utuh dan dikenali sebagai petunjuk Transport.
- AmountParser mengenali satuan, gabungan satuan, desimal, pemisah ribuan,
  angka kata, `setengah juta`, `sejuta`, dan `seribu`. Perhitungan memakai
  `BigInt` dan rasio integer; hasil harus muat dalam integer SQLite 64 bit.
  Tidak ada perhitungan uang dengan `double`.
- Angka tanpa satuan/penanda uang di bawah 1000 diabaikan. Angka pada tanggal,
  nama akun, bilangan porsi/orang, tahun, dan konteks nomor rekening tidak
  menjadi jumlah. Kandidat dengan satuan/penanda uang diutamakan; kandidat
  setara memilih yang pertama dengan `MULTIPLE_AMOUNTS`.
- `35.000`/`35,000` tanpa satuan berarti 35000. Pemisah dengan satuan berarti
  desimal. Bentuk dengan tiga angka pecahan bersatuan seperti `1.000 juta`
  diberi `AMBIGUOUS_SEPARATOR`; pengelompokan tidak baku juga diperingatkan.
  Pecahan rupiah, jumlah negatif, dan overflow tidak diterima sebagai jumlah
  sah dan mendapat warning. Teks tanpa jumlah mendapat `NO_AMOUNT`.
- DateParser memakai kalender dari `Clock.now()`, kemudian menyimpan UTC.
  `SystemClock` memakai waktu lokal perangkat; Clock UTC memakai kalender UTC.
  Satu panggilan `parseMany` membekukan Clock sekali untuk seluruh draf.
  Penanda tanggal biasa mempertahankan jam/menit Clock; pagi/siang/sore/malam
  memakai 07:00/12:00/16:00/20:00. Tanpa penanda tanggal memakai hari ini.
  `senin lalu` berarti Senin pekan sebelumnya, `hari senin` berarti Senin
  pekan berjalan, dan `minggu lalu` berarti tujuh hari sebelumnya.
  Tanggal tidak sah mendapat `INVALID_DATE`; beberapa tanggal memilih yang
  pertama dengan `MULTIPLE_DATES`. Validator tetap memeriksa tanggal terlalu jauh
  di masa depan pada konfirmasi.
- Jenis memakai kata kunci transfer, pemasukan, lalu pengeluaran. `top up`
  menjadi transfer jika menyebut dua akun berbeda; selain itu pengeluaran.
  Tanpa kata kunci, jenis pengeluaran dengan confidence lebih rendah.
- AccountMatcher mengenali nama/alias dan pola `pakai`, `via`, `dari`, `ke`.
  Satu salah ketik diperbolehkan untuk kata akun/alias minimal lima huruf,
  termasuk penyisipan, penghapusan, atau penggantian satu huruf. Pencocokan
  toleran diberi `FUZZY_ACCOUNT`. Transfer memisahkan asal dan tujuan;
  ungkapan `tarik tunai` tidak keliru dianggap penyebutan akun Tunai.
  Tanpa akun eksplisit, akun terakhir yang masih ada diutamakan; memori akun
  dipakai jika tidak ada akun terakhir. Fallback diberi `DEFAULT_ACCOUNT`.
  Nama akun yang disebut tetapi tidak dikenal tidak diam-diam diganti fallback.
- CategoryMatcher memilih memori pengguna sebelum kamus bawaan, hanya untuk
  kategori yang masih tersedia dan sesuai jenis transaksi. Memori lebih
  spesifik didahulukan, lalu count dan waktu pembaruan. Kamus mencakup seluruh
  kata kunci Makanan, Transport, Tagihan, Belanja, Hiburan, Kesehatan, dan Gaji
  yang diminta. Transfer tidak memiliki kategori.
- Catatan adalah sisa teks yang telah dibersihkan dari jumlah, tanggal,
  penyebutan akun, dan penanda uang. `rawText` tetap mempertahankan teks asli.
- Confidence: 0,3 awal, +0,3 jumlah jelas, +0,15 jenis dari kata kunci,
  +0,1 akun cocok, +0,1 kategori cocok, −0,1 setiap warning; dibatasi 0–1.
  Hitungan score memakai poin integer sebelum konversi akhir.

## Memori lokal dan penyimpanan

Schema Drift naik dari 2 ke 3. Migrasi menambahkan
`quick_input_memory(keyword PRIMARY KEY, category_id, account_id, count, updated_at)`.
Memori tidak masuk daftar tabel sinkronisasi maupun antrean outbox. Timestamp
memori disimpan UTC. Reset data dan penghapusan akun yang berhasil menghapusnya;
penghapusan akun yang gagal tetap mempertahankan data lokal.

Saat pengguna menyimpan draf yang dikoreksi, repository memori mempelajari kata
dan pasangan kata yang bermakna dari catatan, serta kategori dan akun hasil
koreksi. Kata penghubung, tanggal, angka kata, dan satuan uang tidak dipelajari.
Simpan tanpa koreksi tidak memperkuat tebakan otomatis. Count bertambah ketika
kata kunci yang sama dipelajari lagi.

`QuickInputActions.save(original: ..., corrected: ...)` membungkus penyimpanan
transaksi dan pembelajaran dalam satu transaksi database. Ledger tetap ditulis
melalui `TransactionActions.save` → `TransactionsRepository.save` yang sudah ada.
Jika pembelajaran gagal, simpan ledger ikut dibatalkan agar percobaan ulang tidak
menggandakan transaksi. UI menampilkan kegagalan secara inline dan mendukung coba
ulang. Tidak ada jalur penulisan transaksi lain.

Kartu konfirmasi dan Edit manual sama-sama memakai integrasi ini. Edit manual
membawa draf awal sebagai `originalDraft`, sehingga koreksi pada kartu sebelum
berpindah ke editor tetap dipelajari. Editor transaksi biasa tetap menggunakan
alur penyimpanan yang sudah ada.

## Verifikasi

Tes parser memakai Clock tetap Kamis 8 Oktober 2026 pukul 10:00 dan akun Tunai,
BCA, GoPay, DANA. Seluruh contoh pada permintaan menjadi kasus tes, ditambah
angka kata, pemisah ambigu, tanpa jumlah, multi transaksi, typo, tanggal tidak
sah, batas integer, prioritas memori, dan Clock yang berubah saat parsing.
Tes integrasi memeriksa migrasi versi 2, persistensi setelah database dibuka
ulang, count, rollback atomik, lokal tanpa outbox, serta koreksi melalui editor.

```powershell
flutter test --no-pub
flutter analyze --no-pub
# Pembuktian langsung dengan Dart VM, tanpa Flutter:
& 'D:\flutter-sdk\bin\cache\dart-sdk\bin\dart.exe' tool/quick_input_parser_smoke.dart
```

Hasil akhir: 381 kasus tes terverifikasi, termasuk 141 tes parser dan 10 tes
memori/integrasi database. Pada run akhir seluruh proyek, 380 tes lulus dan satu
tes PBKDF2 password yang sudah ada mencapai timeout 30 detik. Ketujuh tes pada
berkas password kemudian diulang terpisah dengan batas waktu yang sama dan lulus
dalam 14 detik. Tidak ada perubahan pada kode password untuk mengatasi timeout.
`flutter analyze --no-pub` bersih; smoke test Dart VM juga lulus.

Log verifikasi berada dalam `build/quick-input-parser-*.log`, termasuk
`quick-input-parser-all-tests.log` dan `quick-input-parser-password-retest.log`.
Pemeriksaan baseline
SHA-256 memastikan 238 berkas sumber stabil, shortcut, EXE release, dan installer
stabil tetap identik. Tidak ada peluncuran aplikasi, penggunaan database pengguna,
atau pembuatan installer pada langkah ini. Pemisahan identitas runtime 2.0 sebelum
menjalankan aplikasi berdampingan dijelaskan dalam `PANDUAN_2.0.md`.
