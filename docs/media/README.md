# Gambar dokumentasi

Gambar antarmuka berasal dari `build/ui-previews/` yang dibuat oleh pengujian widget dengan data demo. Email `abiy@example.com`, nominal, tanggal, dan rekening dalam gambar adalah data uji. Berkas konfigurasi cloud, database pengguna, dan kunci signing tidak digunakan.

`ledgy-banner.png` dibuat dari logo Ledgy dan komposisi grafis lokal. `quick-input-demo.gif` adalah ilustrasi animasi alur input cepat dari trailer Ledgy, bukan rekaman aplikasi berjalan. Susunan UI dapat menyesuaikan ukuran layar, platform, dan versi build.

Regenerasi PNG dari root proyek, setelah pratinjau UI tersedia:

```powershell
python tool/generate_readme_assets.py
```

Alat dokumentasi ini memerlukan Pillow dan tidak menjadi dependency aplikasi Flutter. Untuk membuat ulang pratinjau, pengujian terkait berada di `test/dashboard_test.dart`, `test/transaction_editor_test.dart`, `test/draft_confirmation_sheet_test.dart`, `test/settings_security_test.dart`, `test/budget_ui_test.dart`, dan `test/transaction_history_test.dart`.
