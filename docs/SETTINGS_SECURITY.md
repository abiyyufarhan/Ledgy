# Pengaturan dan keamanan — 1.0.2+3

Pengaturan memakai baris datar seperti referensi: ikon di kiri, judul dan
keterangan, kontrol di kanan. Kontrol turun ke baris berikutnya pada layar kecil
atau teks besar. Tombol sinkron berupa satu ikon dengan tooltip; saat bekerja,
tombol menampilkan spinner dan tidak dapat ditekan berulang. Pemilihan profil
penabung sudah dihapus dari Setting dan tetap tersedia di Detail Akun.

Penyempurnaan 1.0.2+3: ikon kiri dan kontrol kanan disejajarkan di tengah vertikal
setiap baris, tanpa padding tambahan di atas ikon. Tombol Ubah password dan switch
sejajar pada layar lebar dan dapat membungkus pada layar sempit. Validasi terbaru:
`build/settings-center-analyze.log`, `build/settings-center-tests.log`, dan
`build/settings-center-windows-build.log`.

## Password Ledgy

Aktifkan Password, isi password baru dan konfirmasinya. Password menerima 8–128
karakter, termasuk A–Z, a–z, angka dan simbol; spasi tidak dihapus secara otomatis.
Password hanya untuk aplikasi di perangkat ini, terpisah dari password akun.
Perubahan/penonaktifan memerlukan password lama. Saat dikunci, konten aplikasi
disembunyikan dari interaksi dan pembaca layar sampai verifikasi berhasil.

Hash memakai PBKDF2-HMAC-SHA256, 600.000 iterasi, salt acak 128 bit dan hasil 256
bit. Proses berjalan di isolate agar UI tetap merespons. Lima percobaan salah
menimbulkan jeda 30 detik yang bertahan setelah restart. Record disimpan lokal
secara atomik bersama pilihan biometrik; tidak disertakan dalam CSV/sinkronisasi.
Database tetap SQLite biasa, sehingga penguncian tampilan tidak mengenkripsi
file keuangan. Password yang terlupa tidak dapat ditampilkan kembali.

## Biometrik

Perangkat tanpa dukungan biometrik tidak dapat mengaktifkan switch. Tombol periksa
ulang tersedia setelah sensor ditambahkan atau pengaturan sistem diperbarui.
Pemeriksaan juga berjalan saat Settings kembali aktif. Aktivasi meminta
autentikasi perangkat; penonaktifan dapat diverifikasi memakai password Ledgy
ketika keduanya diaktifkan. Pengguna dapat membuka aplikasi dengan salah satu
metode jika keduanya aktif.

Android/macOS menggunakan `canCheckBiometrics`, biometrik terdaftar, dan
`biometricOnly`. Windows memakai bridge `com.ledgy.ledgy/biometrics` untuk meminta
Windows Biometric Framework enumerasi sensor sidik jari/wajah/iris, lalu
memeriksa dukungan Windows Hello. Error, service tidak aktif atau faktor yang
tidak didukung menghasilkan tidak tersedia. Dokumentasi Microsoft menjelaskan
bahwa faktor yang tidak didukung dapat menghasilkan daftar kosong:
[WinBioEnumBiometricUnits](https://learn.microsoft.com/en-us/windows/win32/api/winbio/nf-winbio-winbioenumbiometricunits).

`local_auth` Windows tidak menyediakan pemilihan metode autentikasi dan dapat
menawarkan PIN Windows Hello. Ledgy menjelaskan hal itu pada baris Biometrik dan
tetap mensyaratkan sensor, sehingga Hello dengan PIN saja tidak membuka opsi
biometrik. Sumber: [local_auth](https://pub.dev/packages/local_auth).

Pengaturan kunci perangkat dari versi lama dibaca jika record baru belum ada.
Autentikasi lama tetap berlaku sampai pengguna mengganti pengaturannya, untuk
menghindari kehilangan akses pada komputer yang sebelumnya memakai PIN Hello.

## Verifikasi

- `flutter analyze`: bersih.
- `flutter test` pada rilis fitur 1.0.1: 187 pengujian lulus, termasuk salt/hash sungguhan, penolakan
  password salah, perubahan password, penyimpanan SQLite, migrasi pengaturan
  lama, cooldown restart, lifecycle dan perangkat tanpa biometrik.
- Widget test memeriksa penonaktifan switch selama pemeriksaan perangkat,
  konfirmasi password, layar kunci, tombol sinkron minimal, serta layout kecil
  dan skala teks 200%.
- Pratinjau yang diperiksa: `build/ui-previews/settings-1280.png` dan
  `build/ui-previews/settings-360.png`.
- Perataan ikon 1.0.2: 23 pengujian pengaturan, keamanan UI dan sinkronisasi
  lulus, analisis kode bersih, serta instalasi/pemasangan ulang/uninstall lulus.

Log: `build/settings-analyze.log`, `build/settings-all-tests.log`,
`build/settings-ui-tests.log`, dan `build/settings-windows-build.log`.
Pemeriksaan API Windows pada komputer pengembangan tidak menemukan unit biometrik;
hasil tersimpan di `build/settings-biometric-hardware.log`. Build Windows dan
installer 1.0.1+2 berhasil; instalasi, pemasangan ulang, serta uninstall lulus,
dengan 32 hash payload cocok dan 96 ikon lengkap. Lihat
[installer Windows](WINDOWS_INSTALLER.md).
Autentikasi sensor fisik perlu diperiksa di perangkat penerima; pengujian Flutter
memakai simulasi kemampuan sensor dan tidak memicu prompt biometrik pengguna.
