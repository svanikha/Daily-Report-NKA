import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../services/session.dart';
import '../../utils.dart';
import '../../widgets/widgets.dart';
import '../pc/account_screen.dart';
import 'admin_v2_manage.dart';

/// Menu kelola admin.
class AdminManage extends StatelessWidget {
  const AdminManage({super.key});

  @override
  Widget build(BuildContext context) {
    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
        child: Column(children: [
          ListTile(
            leading: const Icon(Icons.flag),
            title: const Text('Set target bulanan'),
            subtitle: const Text('Database, revenue HP, IoT, sosmed, leasing'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => go(const TargetScreen()),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.inventory_2),
            title: const Text('Master produk & harga'),
            subtitle: const Text('Tambah produk, ubah harga, nonaktifkan'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => go(const ProductsScreen()),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.badge),
            title: const Text('Kelola Product Consultant'),
            subtitle: const Text('Tambah PC, pindah toko, reset password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => go(const PcManageScreen()),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.support_agent),
            title: const Text('Store Manager'),
            subtitle: const Text('Daftar per toko, reset password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => go(const SupportManageScreen()),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.beach_access),
            title: const Text('Jadwal offday & izin'),
            subtitle: const Text('Atur offday mingguan semua PC'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => go(const OffdayScreen()),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.location_on),
            title: const Text('Lokasi toko'),
            subtitle: const Text('Koordinat dan radius (default 100 m)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => go(const StoresScreen()),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.checklist),
            title: const Text('Item checklist toko'),
            subtitle: const Text('Tambah, ubah, urutkan, nonaktifkan'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => go(const ChecklistItemsScreen()),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Card(
        child: Column(children: [
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('Ganti password admin'),
            onTap: () => changePasswordDialog(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Keluar', style: TextStyle(color: Colors.red)),
            onTap: () => logout(context),
          ),
        ]),
      ),
    ]);
  }
}

Future<List<Map<String, dynamic>>> _loadPcs({bool includeInactive = false}) async {
  var q = Session.db.from('profiles').select('id,nama,store_id,aktif,auth_uid,email,stores(nama)').eq('role', 'pc');
  if (!includeInactive) q = q.eq('aktif', true);
  final rows = await q.order('nama');
  return asList(rows);
}

String _tokoOf(Map<String, dynamic> p) {
  final s = p['stores'];
  return s is Map ? '${s['nama']}' : '-';
}

// ---------------------------------------------------------------------
// SET TARGET
// ---------------------------------------------------------------------
class TargetScreen extends StatefulWidget {
  const TargetScreen({super.key});

  @override
  State<TargetScreen> createState() => _TargetScreenState();
}

class _TargetScreenState extends State<TargetScreen> {
  DateTime _bulan = monthStart();
  List<Map<String, dynamic>> _pcs = [];
  String _pcId = 'ALL';
  final Map<String, TextEditingController> _ctrl = {for (final d in targetDefs) d.kode: TextEditingController()};
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _pcs = await _loadPcs();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    await _loadValues(_bulan);
  }

  String? get _sourcePc => _pcId == 'ALL' ? (_pcs.isEmpty ? null : _pcs.first['id'] as String) : _pcId;

  Future<void> _loadValues(DateTime bulan) async {
    setState(() => _loading = true);
    try {
      final src = _sourcePc;
      final rows = src == null
          ? <Map<String, dynamic>>[]
          : asList(await Session.db.from('targets').select('jenis,nilai').eq('pc_id', src).eq('bulan', ymd(bulan)));
      final m = {for (final r in rows) r['jenis'] as String: toNum(r['nilai'])};
      for (final d in targetDefs) {
        final v = m[d.kode];
        _ctrl[d.kode]!.text = v == null || v == 0 ? '' : v.round().toString();
      }
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _copyPrev() async {
    final prev = DateTime(_bulan.year, _bulan.month - 1, 1);
    await _loadValues(prev);
    if (mounted) showMsg(context, 'Target ${namaBulan(prev)} disalin. Tekan Simpan untuk menerapkan.');
  }

  Future<void> _save() async {
    final targetsPc = _pcId == 'ALL' ? _pcs.map((p) => p['id'] as String).toList() : [_pcId];
    if (targetsPc.isEmpty) return;
    final ok = await confirmDialog(
      context,
      'Simpan target?',
      'Target ${namaBulan(_bulan)} akan diterapkan ke ${_pcId == 'ALL' ? 'semua PC (${targetsPc.length})' : 'PC terpilih'}.',
      yes: 'Simpan',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final rows = <Map<String, dynamic>>[];
      for (final pc in targetsPc) {
        for (final d in targetDefs) {
          rows.add({
            'pc_id': pc,
            'bulan': ymd(_bulan),
            'jenis': d.kode,
            'nilai': digitsOnly(_ctrl[d.kode]!.text),
            'updated_by': Session.current?.id,
            'updated_at': now,
          });
        }
      }
      await Session.db.from('targets').upsert(rows, onConflict: 'pc_id,bulan,jenis');
      if (mounted) showMsg(context, 'Target tersimpan');
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String>[];
    for (final d in targetDefs) {
      if (!groups.contains(d.grup)) groups.add(d.grup);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Set target bulanan')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Row(children: [
          IconButton(
            onPressed: () {
              _bulan = DateTime(_bulan.year, _bulan.month - 1, 1);
              _loadValues(_bulan);
            },
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(namaBulan(_bulan), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          ),
          IconButton(
            onPressed: () {
              _bulan = DateTime(_bulan.year, _bulan.month + 1, 1);
              _loadValues(_bulan);
            },
            icon: const Icon(Icons.chevron_right),
          ),
        ]),
        DropdownButton<String>(
          isExpanded: true,
          value: _pcId,
          items: [
            const DropdownMenuItem(value: 'ALL', child: Text('Semua PC (target sama)')),
            for (final p in _pcs) DropdownMenuItem(value: p['id'] as String, child: Text('${p['nama']} · ${_tokoOf(p)}', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            setState(() => _pcId = v ?? 'ALL');
            _loadValues(_bulan);
          },
        ),
        if (_pcId == 'ALL')
          const InfoBanner('Angka di bawah diambil dari PC pertama. Simpan akan menimpa target semua PC.'),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(onPressed: _copyPrev, icon: const Icon(Icons.copy), label: const Text('Salin dari bulan lalu')),
        ),
        if (_loading)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else
          for (final g in groups) ...[
            SectionHeader(g),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  for (final d in targetDefs.where((d) => d.grup == g))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: _ctrl[d.kode],
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: d.label,
                          prefixText: d.isRupiah ? 'Rp ' : null,
                          suffixText: d.isRupiah ? null : d.satuan,
                          isDense: true,
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy || _loading ? null : _save,
          icon: busyIcon(_busy, Icons.save),
          label: const Text('Simpan target'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------
// MASTER PRODUK
// ---------------------------------------------------------------------
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _rows = asList(await Session.db.from('products').select().order('grup').order('harga', ascending: false));
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _edit(Map<String, dynamic>? p, String tipe) async {
    final nama = TextEditingController(text: p == null ? '' : '${p['nama']}');
    final grup = TextEditingController(text: p == null ? (tipe == 'HP' ? 'A Series' : '') : '${p['grup']}');
    final harga = TextEditingController(text: p == null ? '' : '${p['harga']}');
    var aktif = p == null ? true : p['aktif'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(p == null ? 'Tambah produk $tipe' : 'Edit produk'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nama, decoration: const InputDecoration(labelText: 'Nama produk')),
              const SizedBox(height: 10),
              TextField(
                controller: grup,
                decoration: InputDecoration(
                  labelText: tipe == 'HP' ? 'Seri (A Series / Reno Series / Find Series)' : 'Jenis (Pad / Watch / Audio / ...)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: harga,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Harga jual', prefixText: 'Rp '),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Aktif (tampil di pilihan PC)'),
                value: aktif,
                onChanged: (v) => setD(() => aktif = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final data = {
      'tipe': tipe,
      'nama': nama.text.trim(),
      'grup': grup.text.trim(),
      'harga': digitsOnly(harga.text),
      'aktif': aktif,
    };
    if ((data['nama'] as String).isEmpty || (data['grup'] as String).isEmpty) {
      if (mounted) showMsg(context, 'Nama dan seri/jenis wajib diisi');
      return;
    }
    try {
      if (p == null) {
        await Session.db.from('products').insert(data);
      } else {
        await Session.db.from('products').update(data).eq('id', p['id'] as Object);
      }
      _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  Widget _list(String tipe) {
    final q = _q.toLowerCase();
    final rows = _rows.where((r) => r['tipe'] == tipe && (q.isEmpty || '${r['nama']}'.toLowerCase().contains(q))).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
      for (final r in rows)
        Card(
          child: ListTile(
            title: Text('${r['nama']}', style: TextStyle(color: r['aktif'] == true ? null : Colors.grey)),
            subtitle: Text('${r['grup']}${r['aktif'] == true ? '' : ' · nonaktif'}'),
            trailing: Text(rupiah(toNum(r['harga'])), style: const TextStyle(fontWeight: FontWeight.w600)),
            onTap: () => _edit(r, tipe),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Master produk'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(104),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cari produk', isDense: true),
                  onChanged: (v) => setState(() => _q = v.trim()),
                ),
              ),
              const TabBar(
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                tabs: [Tab(text: 'HP'), Tab(text: 'IoT')],
              ),
            ]),
          ),
        ),
        floatingActionButton: Builder(
          builder: (ctx) => FloatingActionButton.extended(
            onPressed: () => _edit(null, DefaultTabController.of(ctx).index == 0 ? 'HP' : 'IOT'),
            icon: const Icon(Icons.add),
            label: const Text('Produk'),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [_list('HP'), _list('IOT')]),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// KELOLA PC
// ---------------------------------------------------------------------
class PcManageScreen extends StatefulWidget {
  const PcManageScreen({super.key});

  @override
  State<PcManageScreen> createState() => _PcManageScreenState();
}

class _PcManageScreenState extends State<PcManageScreen> {
  List<Map<String, dynamic>> _pcs = [];
  List<Map<String, dynamic>> _stores = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _pcs = await _loadPcs(includeInactive: true);
      _stores = asList(await Session.db.from('stores').select().order('nama'));
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<int?> _pickStore(int? current) {
    return showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Pilih toko'),
        children: [
          for (final s in _stores)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, toNum(s['id']).toInt()),
              child: Row(children: [
                Icon(toNum(s['id']).toInt() == current ? Icons.radio_button_checked : Icons.radio_button_off, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('${s['nama']}')),
              ]),
            ),
        ],
      ),
    );
  }

  Future<void> _add() async {
    final nama = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Product Consultant'),
        content: TextField(
          controller: nama,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Nama lengkap'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lanjut')),
        ],
      ),
    );
    if (ok != true || nama.text.trim().isEmpty) return;
    final store = await _pickStore(null);
    if (store == null) return;
    try {
      await Session.db.from('profiles').insert({
        'nama': nama.text.trim(),
        'role': 'pc',
        'store_id': store,
        'email': 'pc${DateTime.now().millisecondsSinceEpoch}@dailyreportnka.app',
      });
      _load();
      if (mounted) showMsg(context, 'PC ditambahkan. PC membuat password saat login pertama.');
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  Future<void> _action(Map<String, dynamic> p, String a) async {
    final db = Session.db;
    try {
      if (a == 'toko') {
        final s = await _pickStore(p['store_id'] == null ? null : toNum(p['store_id']).toInt());
        if (s == null) return;
        await db.from('profiles').update({'store_id': s}).eq('id', p['id'] as String);
      } else if (a == 'reset') {
        if (!mounted) return;
        final ok = await confirmDialog(
          context,
          'Reset password?',
          '${p['nama']} akan diminta membuat password baru saat login berikutnya.',
          yes: 'Reset',
        );
        if (!ok) return;
        await db.rpc('admin_reset_password', params: {'p_profile': p['id']});
        if (mounted) showMsg(context, 'Password direset');
      } else if (a == 'aktif') {
        await db.from('profiles').update({'aktif': p['aktif'] != true}).eq('id', p['id'] as String);
      }
      _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kelola Product Consultant')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.person_add), label: const Text('Tambah PC')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
              for (final p in _pcs)
                Card(
                  child: ListTile(
                    title: Text('${p['nama']}', style: TextStyle(color: p['aktif'] == true ? null : Colors.grey)),
                    subtitle: Text(
                      '${_tokoOf(p)}\n${p['auth_uid'] != null ? 'Sudah membuat password' : 'Belum pernah login'}${p['aktif'] == true ? '' : ' · NONAKTIF'}',
                    ),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (a) => _action(p, a),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'toko', child: Text('Pindah toko')),
                        const PopupMenuItem(value: 'reset', child: Text('Reset password')),
                        PopupMenuItem(value: 'aktif', child: Text(p['aktif'] == true ? 'Nonaktifkan' : 'Aktifkan')),
                      ],
                    ),
                  ),
                ),
            ]),
    );
  }
}

// ---------------------------------------------------------------------
// AKUN ADMIN SUPPORT (tab "Akun" saat login sebagai support)
// ---------------------------------------------------------------------
class SupportAccount extends StatelessWidget {
  const SupportAccount({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Session.current;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.support_agent)),
          title: Text(p?.nama ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('Store Manager · ${p?.toko ?? ''}'),
        ),
      ),
      const InfoBanner('Store Manager bisa melihat data dan menerima notifikasi untuk toko sendiri, serta membuat Daily Report SM (ikon di kanan atas). '
          'Perubahan data promotor dilakukan oleh RBM.'),
      Card(
        child: Column(children: [
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('Ganti password'),
            onTap: () => changePasswordDialog(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Keluar', style: TextStyle(color: Colors.red)),
            onTap: () => logout(context),
          ),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------
// KELOLA ADMIN SUPPORT (admin utama)
// ---------------------------------------------------------------------
class SupportManageScreen extends StatefulWidget {
  const SupportManageScreen({super.key});

  @override
  State<SupportManageScreen> createState() => _SupportManageScreenState();
}

class _SupportManageScreenState extends State<SupportManageScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _rows = asList(await Session.db
          .from('profiles')
          .select('id,nama,email,aktif,auth_uid,stores(nama)')
          .eq('role', 'support')
          .order('nama'));
      _error = null;
    } catch (e) {
      _error = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reset(Map<String, dynamic> p) async {
    final ok = await confirmDialog(context, 'Reset password?',
        '${p['nama']} akan membuat password baru saat login berikutnya.', yes: 'Reset');
    if (!ok) return;
    try {
      await Session.db.rpc('admin_reset_password', params: {'p_profile': p['id']});
      if (mounted) showMsg(context, 'Password ${p['nama']} sudah di-reset');
      _load();
    } catch (e) {
      if (mounted) showErr(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Store Manager')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : ListView(padding: const EdgeInsets.all(12), children: [
                  const InfoBanner('Store Manager bisa melihat data dan menerima notifikasi tokonya sendiri, serta mengisi Daily Report SM, '
                      'tanpa bisa mengubah data promotor. Login pertama: pilih nama di tab RBM & SM lalu buat password.'),
                  if (_rows.isEmpty) const EmptyState(icon: Icons.support_agent, text: 'Belum ada Store Manager'),
                  for (final p in _rows)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.support_agent),
                        title: Text('${p['nama']}'),
                        subtitle: Text('${_tokoOf(p)}\n${p['auth_uid'] == null ? 'Belum pernah login' : 'Sudah membuat password'}'),
                        isThreeLine: true,
                        trailing: p['auth_uid'] == null
                            ? null
                            : TextButton(onPressed: () => _reset(p), child: const Text('Reset password')),
                      ),
                    ),
                ]),
    );
  }
}
