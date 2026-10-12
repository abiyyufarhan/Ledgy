# Quick input — langkah 1

Implementasi berada di salinan `ledgy-2.0`. Fase ini menyediakan model draf,
validator, dan UI konfirmasi untuk parser teks, suara, atau struk pada fase berikutnya.

## Model dan validasi

`TransactionDraft` memakai `TransactionType` yang sudah ada, `DraftSource`,
jumlah integer rupiah, dan tanggal nullable yang dinormalisasi ke UTC. Semua
properti final; daftar peringatan/item disalin dan dibuat tidak bisa diubah.
`copyWith` mempertahankan nilai yang tidak diberikan dan mendukung `null` eksplisit
untuk menghapus kolom nullable. `confidence` harus bernilai hingga dalam 0–1.

`DraftValidator.validate(draft, now: ...)` mengembalikan peringatan dengan `code`,
`field`, dan bantuan berbahasa Indonesia. Validasi mencakup jumlah kosong/nonpositif,
akun kosong, tujuan transfer kosong/sama dengan asal, kategori kosong untuk
pemasukan/pengeluaran, serta tanggal lebih dari 24 jam di masa depan. Batas tepat
24 jam diperbolehkan. Tanggal kosong diperbolehkan pada model; kartu konfirmasi
menampilkan waktu saat ini sebagai tanggal awal sehingga waktu yang disimpan
tetap terlihat dan dapat diedit.

Peringatan parser adalah bantuan, bukan penghalang simpan tambahan. Peringatan
pada kolom hilang setelah kolom tersebut dikoreksi. Masalah validator menentukan
apakah Simpan aktif. ID akun/kategori yang tidak tersedia lagi juga harus dipilih
ulang sebelum menyimpan.

## Membuka kartu konfirmasi

Gunakan fungsi ini dari context yang berada dalam `ProviderScope` aplikasi:

```dart
import 'package:ledgy/features/quick_input/domain/transaction_draft.dart';
import 'package:ledgy/features/quick_input/presentation/draft_confirmation_sheet.dart';

final result = await showDraftConfirmationSheet(
  context,
  draft: TransactionDraft(
    type: TransactionType.expense,
    amount: 25000,
    accountId: account.id,
    categoryId: category.id,
    rawText: 'Makan siang 25 ribu dari Tunai',
    source: DraftSource.text,
    confidence: .9,
  ),
);
```

Teks asli tetap terlihat sebagai referensi. Jumlah menggunakan `MoneyText` dengan
pemisah ribuan, semua nilai uang tetap integer. Akun, kategori, jenis, tanggal/jam,
dan catatan dapat dikoreksi. Sumber struk menampilkan item hanya baca di bawah
catatan. Chip keyakinan: tinggi ≥0,8; sedang ≥0,5 dan <0,8; rendah <0,5.
Mobile membuka bottom sheet; Windows/Linux/macOS membuka dialog, termasuk
ketika jendela desktop diperkecil.

Sejak langkah 2, Simpan memakai `QuickInputActions.save`, yang meneruskan ke
`TransactionActions.save` → `TransactionsRepository.save` dan mempelajari koreksi
dalam satu transaksi database atomik. Tidak ada jalur penyimpanan ledger baru;
tabel memori lokal dijelaskan dalam `QUICK_INPUT_STEP2.md`.
Timestamp disimpan UTC, ID dibuat UUID v4, dan transaksi masuk antrean
sinkronisasi yang sudah ada. Teks mentah, keyakinan, peringatan, dan item adalah
metadata draf; skema transaksi lama tidak menyimpan metadata tersebut.

Buang menutup UI tanpa menyimpan. Edit manual menutup kartu lalu membuka
`TransactionEditor` dengan nilai draf terbaru. Draf transfer memakai akun asal
dan tujuan di editor manual; editor biasa tetap mendukung penerima eksternal.
Hasil fungsi berupa `DraftConfirmationResult` (saved/discarded/manual), atau
`null` jika ditutup melalui navigasi sistem. Aksi manual mengembalikan hasil
setelah editor ditutup. Sejak langkah 3, simpan di editor mengembalikan penanda
`saved` dengan draf hasil koreksi; menutup editor tanpa menyimpan mempertahankan
penanda `manual`.

## Verifikasi

```powershell
flutter test test/domain/draft_validator_test.dart test/draft_confirmation_sheet_test.dart test/transaction_editor_test.dart --no-pub
flutter analyze --no-pub
flutter test --no-pub
```

Tes widget memakai database memori dan repository transaksi asli untuk memeriksa
hasil simpan. Tidak ada peluncuran aplikasi, penggunaan database pengguna,
konfigurasi cloud produksi, atau pembuatan installer pada langkah ini.

Hasil verifikasi langkah 1 pada 8 Oktober 2026: seluruh 230 tes proyek lulus (termasuk 23 tes domain draf
dan 20 tes widget konfirmasi), analisis kode bersih. Tes mencakup koreksi seluruh
isian, timestamp UTC, transfer, edit manual, kegagalan simpan/coba ulang,
pencegahan klik ganda, kondisi pilihan memuat/kosong/error, serta font 200%.
Log tersedia pada `build/quick-input-all-tests.log` dan
`build/quick-input-analyze.log`. Pemeriksaan SHA-256 di
`build/quick-input-stable-baseline-check.log` memastikan 238 berkas sumber,
shortcut, EXE release, dan installer proyek stabil tetap identik.
