/// Shared by the transaction editor and filters; no category is written until
/// a transaction is saved.
const expenseCategoryGroups = <String, List<String>>{
  'Acara Sosial': ['Amal & Donasi', 'Hadiah', 'Pemakaman', 'Pernikahan'],
  'Belanja': ['Belanja Bulanan', 'Fashion', 'Gadget & Elektronik'],
  'Cicilan': ['Kendaraan', 'Pinjaman', 'Rumah'],
  'Hiburan': [
    'Film/Musik',
    'Games',
    'Hobi',
    'Konser',
    'Layanan Streaming',
    'Liburan',
    'Nongkrong',
  ],
  'Keluarga': [
    'Asisten Rumah Tangga',
    'Kebutuhan Anak',
    'Kebutuhan Orang Tua',
    'Laundry',
    'Peliharaan',
    'Renovasi',
  ],
  'Kesehatan': [
    'Biaya Dokter',
    'Gym/Fitness',
    'Obat',
    'Olahraga',
    'Perawatan Diri',
  ],
  'Makan & Minum': ['Cafe / Warkop', 'Pesanan Makanan', 'Restoran'],
  'Pembayaran Pinjaman': [],
  'Pendidikan': ['Buku', 'Uang Sekolah / Kuliah'],
  'Tabungan': [
    'Dana Darurat',
    'Investasi',
    'Liburan',
    'Pendidikan',
    'Pensiun',
    'Rumah',
  ],
  'Tagihan': [
    'Air',
    'Asuransi',
    'Biaya Pemeliharaan',
    'Gas',
    'Internet',
    'Kartu Kredit',
    'Langganan',
    'Listrik',
    'Pulsa & Data',
    'Sewa',
    'TV Kabel',
  ],
  'Top Up': ['DANA', 'GoPay', 'OVO', 'ShopeePay'],
  'Transportasi': [
    'Bensin',
    'Biaya Parkir',
    'Servis Kendaraan',
    'Taksi / Ojol',
    'Tiket Perjalanan',
    'Transportasi Publik',
  ],
  'Lainnya': [
    'Biaya',
    'Pajak',
    'Pelunasan',
    'Tarik Tunai',
    'Top Up Kartu',
    'Uang Keluar',
  ],
};

const incomeCategoryGroups = <String, List<String>>{
  'Acara Sosial': ['Amal & Donasi', 'Hadiah'],
  'Pemasukan': [
    'Bonus',
    'Gaji',
    'Laba Atas Investasi',
    'Laba Usaha',
    'Pendapatan Tambahan',
    'Tunjangan / Uang Saku',
    'Uang Masuk',
  ],
  'Pencairan Pinjaman': [],
  'Tabungan': ['Investasi'],
  'Lainnya': ['Bunga', 'Cashback', 'Pelunasan', 'Penggantian Biaya', 'Refund'],
};

/// Places legacy standalone income names (for example Gaji) in the catalog.
String incomeCategoryName(String name) {
  final trimmed = name.trim();
  if (!trimmed.contains('•')) {
    for (final entry in incomeCategoryGroups.entries) {
      if (entry.value.contains(trimmed)) return '${entry.key} • $trimmed';
    }
  }
  return trimmed;
}
