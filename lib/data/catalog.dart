const kategoriUser = ['A Series', 'Reno Series', 'Find Series', 'IoT'];

const statusUser = ['Asking', 'Probing', 'Closing'];

const statusDesc = {
  'Asking': 'User yang masih bertanya secara online',
  'Probing': 'User yang sudah diprospek, online maupun offline',
  'Closing': 'User yang sudah membeli',
};

class SosmedDef {
  final String kode;
  final String platform;
  final String aktivitas;
  final String satuan;
  const SosmedDef(this.kode, this.platform, this.aktivitas, this.satuan);
  String get label => '$platform - $aktivitas';
}

const sosmedDefs = [
  SosmedDef('fb_posting', 'FB Marketplace', 'Posting', 'kali'),
  SosmedDef('tiktok_konten', 'TikTok', 'Konten diupload', 'konten'),
  SosmedDef('tiktok_live', 'TikTok', 'Live', 'kali'),
  SosmedDef('ig_story', 'Instagram', 'Update story', 'kali'),
  SosmedDef('wa_story', 'WhatsApp', 'Update story', 'kali'),
];

SosmedDef? sosmedByKode(String? kode) {
  for (final d in sosmedDefs) {
    if (d.kode == kode) return d;
  }
  return null;
}

const leasingList = ['HCI', 'Kredivo', 'Indodana', 'Yesscredit', 'Kreditplus', 'Akulaku', 'Avanto'];

/// Pilihan detail pembayaran penjualan HP (disimpan di kolom sales.leasing).
const cashViaList = ['Transfer', 'Tunai', 'OMO'];
const kreditViaList = [...leasingList, 'Blibli', 'OMO'];

class TargetDef {
  final String kode;
  final String label;
  final String satuan; // rupiah | unit | kontak | kali | konten
  final String grup;
  const TargetDef(this.kode, this.label, this.satuan, this.grup);
  bool get isRupiah => satuan == 'rupiah';
}

final List<TargetDef> targetDefs = [
  const TargetDef('database_baru', 'Penambahan database baru', 'kontak', 'Database & Report'),
  const TargetDef('revenue_hp', 'Revenue HP', 'rupiah', 'Database & Report'),
  const TargetDef('iot_unit', 'IoT', 'unit', 'Database & Report'),
  for (final s in sosmedDefs) TargetDef(s.kode, s.label, s.satuan, 'Sosmed'),
  for (final l in leasingList) TargetDef('leasing_$l', 'Cek limit $l', 'kali', 'Leasing'),
];

const channelLabel = {
  'telepon': 'Telepon',
  'whatsapp': 'WhatsApp',
  'wa_bisnis': 'WhatsApp Business',
  'status': 'Perubahan status',
};
