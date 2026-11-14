import 'package:flutter/material.dart';

import '../../data/nka.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';

/// Atur jenis activity dan kewajiban harian activity PC per area.
/// TL / Trainer: areanya. PIC NKA / Manajer Trainer: semua area.
class KewajibanScreen extends StatefulWidget {
  const KewajibanScreen({super.key});

  @override
  State<KewajibanScreen> createState() => _KewajibanScreenState();
}

class _KewajibanScreenState extends State<KewajibanScreen> {
  List<Map<String, dynamic>> _areas = [];
  int? _area;
  List<SosmedDef> _jenis = [];
  final Map<String, int> _target = {};
  bool _loading = true;
  bool _saving = false;
  bool _ubah = false;
  String? _error;

  Profile get me => Session.current!;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _areas = asList(await Session.db.from('areas').select('id,nama').order('id'));
      if (!me.isPic) _areas = _areas.where((a) => toNum(a['id']).toInt() == me.areaId).toList();
      _area = _areas.isEmpty ? null : toNum(_areas.first['id']).toInt();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = errMsg(e));
    }
  }

  Future<void> _load() async {
    if (_area == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      await muatJenisActivity();
      _jenis = jenisActivityArea(_area);
      final rows = asList(await Session.db.from('kewajiban_activity').select('kode,target').eq('area_id', _area!));
      _target
        ..clear()
        ..addAll({for (final r in rows) '${r['kode']}': toNum(r['target']).toInt()});
      _ubah = false;
      _error = null;
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  String get _namaArea => '${_areas.firstWhere((a) => toNum(a['id']).toInt() == _area, orElse: () => {'nama': ''})['nama']}';

  bool _bolehUbahJenis(SosmedDef d) => me.isPic || (d.areaId != null && d.areaId == me.areaId);

  void _set(String kode, int v) => setState(() {
        _target[kode] = v < 0 ? 0 : v;
        _ubah = true;
      });

  Future<void> _simpan() async {
    setState(() => _saving = true);
    try {
      await Session.db.rpc('simpan_kewajiban', params: {
        'p_area': _area,
        'p_items': {for (final e in _target.entries) if (e.value > 0) e.key: e.value},
      });
      if (mounted) showMsg(context, 'Kewajiban activity area $_namaArea tersimpan');
      await _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _formJenis([SosmedDef? d]) async {
    final nama = TextEditingController(text: d?.nama ?? '');
    final satuan = TextEditingController(text: d?.satuan ?? 'kali');
    // PIC: boleh semua area (null) atau area terpilih. TL/Trainer: hanya areanya.
    int? untukArea = d == null ? (me.isPic ? null : _area) : d.areaId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(d == null ? 'Activity baru' : 'Ubah activity'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nama,
              autofocus: d == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nama activity *', hintText: 'Misal: YouTube Shorts - Upload'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: satuan,
              decoration: const InputDecoration(labelText: 'Satuan', hintText: 'kali / konten / orang'),
            ),
            if (me.isPic) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<int?>(
                initialValue: untukArea,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Berlaku untuk'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Semua area')),
                  for (final a in _areas)
                    DropdownMenuItem<int?>(value: toNum(a['id']).toInt(), child: Text('Area ${a['nama']} saja')),
                ],
                onChanged: (v) => setD(() => untukArea = v),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Berlaku untuk PC area $_namaArea', style: Theme.of(ctx).textTheme.bodySmall),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
          ],
        ),
      ),
    );
    final n = nama.text.trim();
    final s = satuan.text.trim();
    nama.dispose();
    satuan.dispose();
    if (ok != true) return;
    if (n.isEmpty) {
      if (mounted) showMsg(context, 'Nama activity wajib diisi');
      return;
    }
    try {
      await Session.db.rpc('simpan_jenis_activity', params: {
        'p_kode': d?.kode,
        'p_nama': n,
        'p_satuan': s,
        'p_area': untukArea,
      });
      if (mounted) showMsg(context, d == null ? 'Activity "$n" ditambahkan' : 'Activity diperbarui');
      await _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  Future<void> _hapusJenis(SosmedDef d) async {
    final ok = await confirmDialog(context, 'Hapus activity "${d.nama}"?',
        'Activity tidak bisa dipilih PC lagi dan kewajibannya dihapus. Riwayat yang sudah diinput tetap tersimpan.',
        yes: 'Hapus');
    if (!ok) return;
    try {
      await Session.db.rpc('hapus_jenis_activity', params: {'p_kode': d.kode});
      await _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activity & kewajiban PC')),
      floatingActionButton: _loading || _area == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _formJenis(),
              icon: const Icon(Icons.add),
              label: const Text('Activity baru'),
            ),
      bottomNavigationBar: !_ubah
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _simpan,
                  icon: busyIcon(_saving, Icons.save),
                  label: Text('Simpan kewajiban area $_namaArea'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ),
      body: _error != null
          ? ErrorRetry(error: _error!, onRetry: _init)
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
                  if (_areas.length > 1)
                    DropdownButtonFormField<int>(
                      initialValue: _area,
                      decoration: const InputDecoration(labelText: 'Area', prefixIcon: Icon(Icons.map), isDense: true),
                      items: [
                        for (final a in _areas) DropdownMenuItem(value: toNum(a['id']).toInt(), child: Text('${a['nama']}')),
                      ],
                      onChanged: (v) {
                        _area = v;
                        _load();
                      },
                    )
                  else
                    Text('Area $_namaArea', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  const InfoBanner(
                    'Isi target HARIAN tiap PC di area ini. 0 = tidak wajib. PC melihat progresnya di menu Activity '
                    'dan dashboard. Tekan "Activity baru" untuk menambah jenis activity selain yang sudah ada.',
                    icon: Icons.flag,
                  ),
                  const SectionHeader('Activity'),
                  for (final d in _jenis) _baris(d.kode, d.nama, d.satuan, jenis: d),
                  const SectionHeader('Cek limit leasing'),
                  _baris('cek_limit', 'Cek limit (semua leasing)', 'pengajuan'),
                  for (final l in leasingList) _baris('cek:$l', 'Cek limit $l', 'pengajuan'),
                ]),
    );
  }

  Widget _baris(String kode, String nama, String satuan, {SosmedDef? jenis}) {
    final v = _target[kode] ?? 0;
    final umum = jenis != null && jenis.areaId == null;
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nama, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                [
                  v > 0 ? 'Wajib $v $satuan/hari' : 'Tidak wajib',
                  if (jenis != null) umum ? 'semua area' : 'khusus area ini',
                ].join(' · '),
                style: TextStyle(fontSize: 11.5, color: v > 0 ? Colors.green.shade700 : Colors.grey.shade600),
              ),
            ]),
          ),
          if (jenis != null && _bolehUbahJenis(jenis))
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (a) => a == 'ubah' ? _formJenis(jenis) : _hapusJenis(jenis),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'ubah', child: Text('Ubah nama / satuan')),
                PopupMenuItem(value: 'hapus', child: Text('Hapus activity')),
              ],
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: v > 0 ? () => _set(kode, v - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 30,
            child: Text('$v', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _set(kode, v + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ]),
      ),
    );
  }
}
