import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/nka.dart';
import '../../services/photo_service.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/photo_widgets.dart';
import '../../widgets/widgets.dart';
import '../riwayat_screens.dart';

/// Activity toko pada satu tanggal: report sosmed (dengan screenshot) dan cek limit leasing
/// (dengan selfie bersama sales leasing). Sama dengan modul Activity di Daily Report OS.
class ActivityScreen extends StatefulWidget {
  final TokoHari toko;
  const ActivityScreen({super.key, required this.toko});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _sosmed = [];
  List<Map<String, dynamic>> _leasing = [];
  final Map<String, List<Map<String, dynamic>>> _foto = {};

  TokoHari get t => widget.toko;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _sosmed.isEmpty && _leasing.isEmpty;
      _error = null;
    });
    try {
      final db = Session.db;
      final res = await Future.wait<dynamic>([
        db.from('social_activities').select().eq('store_id', t.storeId).eq('tanggal', t.tgl).order('created_at'),
        db.from('leasing_checks').select().eq('store_id', t.storeId).eq('tanggal', t.tgl).order('created_at'),
      ]);
      _sosmed = asList(res[0]);
      _leasing = asList(res[1]);
      final ids = [..._sosmed, ..._leasing].map((r) => r['id'] as String).toList();
      _foto.clear();
      if (ids.isNotEmpty) {
        final rows = asList(await db.from('photos').select('ref_id,path,sumber,flags').inFilter('ref_id', ids).order('created_at'));
        for (final p in rows) {
          _foto.putIfAbsent('${p['ref_id']}', () => []).add(p);
        }
      }
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _tambah(Widget form) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => form));
    if (ok == true) _load();
  }

  Future<void> _hapus(String tabel, Map<String, dynamic> r, String judul) async {
    final ok = await confirmDialog(context, 'Hapus $judul?', 'Data dan fotonya akan dihapus.', yes: 'Hapus');
    if (!ok) return;
    try {
      await Session.db.from('photos').delete().eq('ref_id', r['id'] as String);
      await Session.db.from(tabel).delete().eq('id', r['id'] as String);
      _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  void _lihatFoto(Map<String, dynamic> r, String judul) {
    final f = _foto['${r['id']}'] ?? const [];
    if (f.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoViewerPage(photos: f, title: judul)));
  }

  @override
  Widget build(BuildContext context) {
    final boleh = t.bolehIsiHarian;
    final approve = _leasing.where((l) => l['hasil'] == 'Approve').length;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Activity'),
          Text('${t.toko} · ${tglPendek(t.tanggal)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ]),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RiwayatCekLimitScreen(storeId: t.storeId, judul: t.toko),
            )),
            icon: const Icon(Icons.history),
            label: const Text('Riwayat cek limit'),
          ),
        ],
      ),
      bottomNavigationBar: !boleh || _loading || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _tambah(SosmedForm(toko: t)),
                      icon: const Icon(Icons.campaign),
                      label: const Text('+ Sosmed'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => _tambah(LeasingForm(toko: t)),
                      icon: const Icon(Icons.fact_check),
                      label: const Text('+ Cek limit'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    ),
                  ),
                ]),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(12), children: [
                    if (!boleh) InfoBanner(t.alasanTerkunci, icon: Icons.lock_outline),
                    SectionHeader('Report sosmed (${_sosmed.fold<num>(0, (a, r) => a + toNum(r['jumlah']))})'),
                    if (_sosmed.isEmpty) const EmptyState(text: 'Belum ada report sosmed', icon: Icons.campaign),
                    for (final r in _sosmed) _sosmedTile(r, boleh),
                    SectionHeader('Cek limit leasing (${_leasing.length} · $approve approve)'),
                    if (_leasing.isEmpty) const EmptyState(text: 'Belum ada cek limit', icon: Icons.fact_check),
                    for (final r in _leasing) _leasingTile(r, boleh),
                  ]),
                ),
    );
  }

  Widget _sosmedTile(Map<String, dynamic> r, bool boleh) {
    final d = sosmedByKode(r['kode'] as String?);
    final judul = d?.label ?? '${r['kode']}';
    final foto = _foto['${r['id']}'] ?? const [];
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: const Icon(Icons.campaign),
        title: Text(judul),
        subtitle: Text([
          '${r['jumlah']} ${d?.satuan ?? 'kali'}',
          '${foto.length} screenshot',
          if (r['link'] != null) '${r['link']}',
        ].join(' · ')),
        onTap: () => _lihatFoto(r, judul),
        trailing: boleh
            ? IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _hapus('social_activities', r, judul))
            : null,
      ),
    );
  }

  Widget _leasingTile(Map<String, dynamic> r, bool boleh) {
    final ok = r['hasil'] == 'Approve';
    final judul = 'Cek limit ${r['leasing']}';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? Colors.green.shade700 : Colors.red.shade700),
        title: Text('${r['leasing']}'),
        subtitle: Text(ok ? 'Approve · limit ${rupiah(toNum(r['limit_disetujui']))}' : 'Reject'),
        onTap: () => _lihatFoto(r, 'Selfie $judul'),
        trailing: boleh
            ? IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _hapus('leasing_checks', r, judul))
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------
// FORM REPORT SOSMED
// ---------------------------------------------------------------------
class SosmedForm extends StatefulWidget {
  final TokoHari toko;
  const SosmedForm({super.key, required this.toko});

  @override
  State<SosmedForm> createState() => _SosmedFormState();
}

class _SosmedFormState extends State<SosmedForm> {
  String _kode = sosmedDefs.first.kode;
  final _jumlah = TextEditingController(text: '1');
  final _link = TextEditingController();
  List<PickedPhoto> _photos = [];
  bool _busy = false;

  @override
  void dispose() {
    _jumlah.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final jumlah = int.tryParse(_jumlah.text.trim()) ?? 0;
    if (jumlah <= 0) {
      showMsg(context, 'Jumlah minimal 1');
      return;
    }
    if (_photos.isEmpty) {
      showMsg(context, 'Upload minimal 1 screenshot sebagai bukti');
      return;
    }
    setState(() => _busy = true);
    try {
      final link = _link.text.trim();
      final row = await Session.db
          .from('social_activities')
          .insert({
            'store_id': widget.toko.storeId,
            'pc_id': widget.toko.pcId,
            'diinput_oleh': Session.current!.id,
            'tanggal': widget.toko.tgl,
            'kode': _kode,
            'jumlah': jumlah,
            'link': link.isEmpty ? null : link,
          })
          .select('id')
          .single();
      await PhotoService.saveAll(
        storeId: widget.toko.storeId,
        pcId: widget.toko.pcId,
        refTabel: 'social_activities',
        refId: row['id'] as String,
        photos: _photos,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final def = sosmedByKode(_kode)!;
    return Scaffold(
      appBar: AppBar(title: const Text('Report sosmed')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('${widget.toko.toko} · ${hariTgl(widget.toko.tanggal)}'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _kode,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Aktivitas *'),
          items: [for (final d in sosmedDefs) DropdownMenuItem(value: d.kode, child: Text(d.label))],
          onChanged: (v) => setState(() => _kode = v ?? _kode),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _jumlah,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: 'Jumlah (${def.satuan}) *'),
        ),
        if (_kode.startsWith('tiktok')) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _link,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Link konten (opsional)'),
          ),
        ],
        const SizedBox(height: 16),
        PhotoPickerField(
          label: 'Screenshot bukti * (kamera atau galeri, hari ini)',
          photos: _photos,
          photoLabel: def.label,
          kind: PhotoKind.screenshot,
          toko: widget.toko.toko,
          onChanged: (p) => setState(() => _photos = p),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: (_busy || _photos.isEmpty) ? null : _save,
          icon: busyIcon(_busy, Icons.cloud_upload),
          label: Text(_photos.isEmpty ? 'Upload bukti dulu' : 'Simpan'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------
// FORM CEK LIMIT LEASING
// ---------------------------------------------------------------------
class LeasingForm extends StatefulWidget {
  final TokoHari toko;
  const LeasingForm({super.key, required this.toko});

  @override
  State<LeasingForm> createState() => _LeasingFormState();
}

class _LeasingFormState extends State<LeasingForm> {
  String? _leasing;
  String _hasil = 'Approve';
  final _limit = TextEditingController();
  List<PickedPhoto> _photos = [];
  bool _busy = false;

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_leasing == null) {
      showMsg(context, 'Pilih leasing');
      return;
    }
    final limit = digitsOnly(_limit.text);
    if (_hasil == 'Approve' && limit <= 0) {
      showMsg(context, 'Isi limit yang didapat');
      return;
    }
    if (_photos.isEmpty) {
      showMsg(context, 'Foto selfie dengan sales leasing wajib diupload');
      return;
    }
    setState(() => _busy = true);
    try {
      final row = await Session.db
          .from('leasing_checks')
          .insert({
            'store_id': widget.toko.storeId,
            'pc_id': widget.toko.pcId,
            'diinput_oleh': Session.current!.id,
            'tanggal': widget.toko.tgl,
            'leasing': _leasing,
            'hasil': _hasil,
            'limit_disetujui': _hasil == 'Approve' ? limit : null,
          })
          .select('id')
          .single();
      await PhotoService.saveAll(
        storeId: widget.toko.storeId,
        pcId: widget.toko.pcId,
        refTabel: 'leasing_checks',
        refId: row['id'] as String,
        photos: _photos,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report cek limit leasing')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('${widget.toko.toko} · ${hariTgl(widget.toko.tanggal)}'),
        const SizedBox(height: 12),
        const Text('Leasing *', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final l in leasingList)
            ChoiceChip(label: Text(l), selected: _leasing == l, onSelected: (_) => setState(() => _leasing = l)),
        ]),
        const SizedBox(height: 16),
        const Text('Hasil *', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'Approve', label: Text('Approve'), icon: Icon(Icons.check_circle)),
            ButtonSegment(value: 'Reject', label: Text('Reject'), icon: Icon(Icons.cancel)),
          ],
          selected: {_hasil},
          onSelectionChanged: (s) => setState(() => _hasil = s.first),
        ),
        if (_hasil == 'Approve') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _limit,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Limit yang didapat (Rp) *', prefixText: 'Rp '),
          ),
        ],
        const SizedBox(height: 16),
        PhotoPickerField(
          label: 'Foto selfie dengan sales leasing *',
          photos: _photos,
          max: 1,
          selfie: true,
          photoLabel: 'Leasing ${_leasing ?? ''}',
          toko: widget.toko.toko,
          onChanged: (p) => setState(() => _photos = p),
        ),
        const SizedBox(height: 4),
        Text('Tanggal, jam, lokasi, nama, dan toko otomatis ditempel di foto. Foto galeri harus diambil hari ini.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: (_busy || _photos.isEmpty) ? null : _save,
          icon: busyIcon(_busy, Icons.cloud_upload),
          label: Text(_photos.isEmpty ? 'Upload selfie dulu' : 'Simpan'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ]),
    );
  }
}
