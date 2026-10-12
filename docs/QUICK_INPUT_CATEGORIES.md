# Kategori otomatis: Cafe / Warkop

Input `minum kopi 35rb via GoPay` memilih **Makan & Minum • Cafe / Warkop**
pada kartu konfirmasi. Kata `kopi`, `ngopi`, `warkop`, `cafe`, `kafe`, dan
`coffee` memakai aturan yang sama. Input `minum kopi` juga menentukan kategori,
tetapi jumlah tetap harus diisi sebelum menyimpan. Semua berjalan lokal melalui
ParserPipeline, tanpa AI atau jaringan.

Memori pilihan pengguna tetap diprioritaskan di atas kamus. Bila pengguna
mengoreksi kategori lalu menyimpan, kata kunci yang dipelajari dapat menentukan
kategori pada input berikutnya. Cafe / Warkop lebih spesifik daripada induk
Makan & Minum. Subkategori lain tidak otomatis mewarisi seluruh kata kunci
induk; misalnya Restoran tidak dipilih hanya karena teks mengandung kopi.

`QuickInputCategories` menyediakan pilihan Cafe / Warkop dengan UUID sementara
yang stabil selama sesi provider, jika kategorinya belum ada di database.
Membuka atau membuang draf tidak menulis kategori maupun transaksi. Saat Simpan,
kategori dibuat melalui CategoriesRepository dalam transaksi database yang sama
dengan penyimpanan ledger melalui TransactionRepository dan pembelajaran lokal.
Kegagalan membatalkan ketiganya. Kategori yang sudah ada, termasuk penulisan
lama `Cafe /Warkop`, dipakai kembali. Resolusi ID sendiri tidak dihitung sebagai
koreksi pengguna untuk memori.

ID pratinjau tidak digunakan sebagai ID tersimpan. Jika kategori harus dibuat,
Simpan memakai UUID baru; kategori yang diarsipkan tidak diaktifkan ulang oleh
ID pratinjau lama. Kategori aktif yang sudah ada tetap dipakai kembali.

Kategori pratinjau juga dibawa ke Edit manual. Hasil konfirmasi mengembalikan
ID kategori yang benar-benar tersimpan jika kategori sudah dibuat sebelumnya
selama pengguna meninjau draf. Model draf dan skema database tidak berubah.

Tes mencakup variasi kalimat, batas kata (`fotokopi` bukan kopi), fallback
ke induk saat konteks domain tidak memiliki Cafe, memori pengguna, pratinjau
tanpa penulisan, context provider yang sebenarnya, reuse kategori, rollback,
dan alur Simpan/Edit manual/Buang. Log: `build/quick-input-cafe-*.log`.

Input bar menjaga context provider tetap diamati dengan `listenManual` selama
proses konfirmasi, lalu menutup langganan pada akhir proses. Ini mencegah
dependency stream yang tidak diamati dijeda sebelum context selesai dimuat.
Pengujian memakai context provider dan repository sebenarnya, bukan hanya
context siap pakai dalam tes widget.

Verifikasi: seluruh 445 tes lulus (18 tes baru), analisis kode tidak menemukan
masalah, dan SHA-256 238 berkas sumber serta tiga artefak rilis versi stabil
tetap identik dengan baseline.

Build debug Windows berhasil, tersedia di
`build/windows/x64/runner/Debug/ledgy_2_0.exe`. Tidak ada pemasangan atau
peluncuran aplikasi pada langkah ini; identitas produk tetap **Ledgy 2.0**.
