# Asal dan anotasi korpus

`phrases.csv` berisi 120 contoh sintetis kalimat transaksi sehari-hari dalam
bahasa Indonesia. Kalimat dibuat untuk pengujian; bukan riwayat pribadi pengguna
atau klaim bahwa asisten melakukan transaksi tersebut. Enam kasus tanpa jumlah
disertakan untuk mengukur penolakan nominal palsu.

Clock tetap: Kamis 8 Oktober 2026 10:00 UTC. Tanggal CSV adalah tanggal kalender
di zona waktu clock, format YYYY-MM-DD; jam diuji terpisah pada unit DateParser.
Akun: Tunai, BCA, GoPay, DANA. Akun terakhir Tunai. Kategori memakai nama katalog
uji, tanpa memori koreksi. Kategori/nominal kosong berarti memang belum diketahui;
transfer tidak memiliki kategori. Kolom akun adalah akun asal (tujuan transfer
diuji terpisah dalam transaction_parser_test.dart).

Untuk data nyata, tambahkan kalimat yang benar-benar diketik beserta anotasi
manual. Kegagalan lokal hanya menyimpan teks sehingga jumlah, kategori, akun,
dan tanggal harus ditandai manusia sebelum masuk CSV. Jangan membuat expected
dari output parser. Simpan sebagian kalimat nyata sebagai korpus evaluasi yang
tidak dipakai saat mengubah aturan, agar angka akurasi tidak hanya mencerminkan
korpus yang digunakan untuk perbaikan.

Koma di dalam kalimat harus dikutip sesuai CSV, misalnya
`"belanja 2,5jt BCA",expense,2500000,Belanja,BCA,2026-10-08`.
Hasil tes: build/parser-corpus-report.json dan build/receipt-corpus-report.json.
