import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../services/presence_service.dart';
import '../services/session.dart';
import '../theme.dart';
import '../utils.dart';
import '../widgets/widgets.dart';
import 'session_gate.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  List<Map<String, dynamic>> _profiles = [];
  bool _loading = true;
  String? _loadError;
  // Versi web hanya untuk admin dan admin support.
  bool _isAdmin = kIsWeb;
  String? _selectedId;
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final res = await Session.db.rpc('list_login_profiles');
      _profiles = asList(res);
    } catch (e) {
      _loadError = errMsg(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _pcs => _profiles.where((p) => p['role'] == 'pc').toList();

  /// PIC NKA di urutan pertama, lalu Trainer, lalu TL.
  List<Map<String, dynamic>> get _admins => [
        ..._profiles.where((p) => p['role'] == 'pic'),
        ..._profiles.where((p) => p['role'] == 'trainer'),
        ..._profiles.where((p) => p['role'] == 'tl'),
      ];

  static String _atasanLabel(Map<String, dynamic> p) => switch (p['role']) {
        'pic' => '${p['nama']} (${p['jabatan'] ?? 'PIC NKA'})',
        'trainer' => '${p['nama']} (Trainer ${p['area']})',
        'tl' => '${p['nama']} (TL ${p['area']})',
        _ => '${p['nama']}',
      };

  String? _adminId;

  Map<String, dynamic>? get _admin => _admins.where((p) => p['id'] == _adminId).firstOrNull ?? _admins.firstOrNull;

  Map<String, dynamic>? get _selected =>
      _isAdmin ? _admin : _pcs.where((p) => p['id'] == _selectedId).firstOrNull;

  /// PC, TL, dan Trainer membuat password sendiri saat login pertama. Akun PIC NKA dibuat di Supabase.
  /// Akun berjabatan (Manajer Trainer) juga membuat password sendiri.
  bool get _needCreate =>
      _selected != null &&
      (_selected!['role'] != 'pic' || _selected!['jabatan'] != null) &&
      _selected!['sudah_daftar'] != true;

  Future<void> _submit() async {
    final p = _selected;
    if (p == null) {
      showMsg(context, _isAdmin ? 'Pilih nama TL / Trainer / PIC NKA terlebih dahulu' : 'Pilih nama terlebih dahulu');
      return;
    }
    final pw = _pw.text;
    if (pw.length < 6) {
      showMsg(context, 'Password minimal 6 karakter');
      return;
    }
    if (_needCreate && pw != _pw2.text) {
      showMsg(context, 'Konfirmasi password tidak sama');
      return;
    }
    setState(() => _busy = true);
    final auth = Session.db.auth;
    try {
      if (_needCreate) {
        final res = await auth.signUp(email: p['email'] as String, password: pw);
        if (res.session == null) {
          throw 'Akun dibuat, tetapi login otomatis gagal. Minta PIC NKA mematikan "Confirm email" di Supabase.';
        }
      } else {
        await auth.signInWithPassword(email: p['email'] as String, password: pw);
      }
      final prof = await Session.load();
      if (prof == null) {
        await auth.signOut();
        throw 'Akun belum terhubung ke data. Hubungi Trainer atau PIC NKA.';
      }
      await PresenceService.login();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => homeFor(prof)),
        (_) => false,
      );
    } on AuthException catch (e) {
      if (mounted) {
        final m = e.message.toLowerCase();
        showMsg(
          context,
          m.contains('invalid login') ? 'Password salah' : (m.contains('already') ? 'Akun sudah terdaftar. Muat ulang lalu masukkan password.' : e.message),
        );
      }
    } catch (e) {
      if (mounted) showErr(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selected;
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? ErrorRetry(error: 'Tidak bisa terhubung ke server.\n$_loadError', onRetry: _load)
                : ListView(padding: const EdgeInsets.all(24), children: [
                    const SizedBox(height: 24),
                    const Icon(Icons.assignment_turned_in, size: 64, color: brandGreen),
                    const SizedBox(height: 8),
                    Text(
                      'Daily Report NKA',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: brandGreen),
                    ),
                    const Text('Erafone · OPPO Big Sampit', textAlign: TextAlign.center),
                    const SizedBox(height: 32),
                    if (kIsWeb)
                      const InfoBanner(
                        'Versi web untuk TL, Trainer, dan PIC NKA. Product Consultant memakai aplikasi di HP.',
                        icon: Icons.laptop,
                      )
                    else
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Product Consultant'), icon: Icon(Icons.person)),
                        ButtonSegment(value: true, label: Text('TL · Trainer · PIC'), icon: Icon(Icons.admin_panel_settings)),
                      ],
                      selected: {_isAdmin},
                      onSelectionChanged: (s) => setState(() {
                        _isAdmin = s.first;
                        _pw.clear();
                        _pw2.clear();
                      }),
                    ),
                    const SizedBox(height: 20),
                    if (!_isAdmin)
                      DropdownButtonFormField<String>(
                        initialValue: _selectedId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Nama Product Consultant'),
                        items: [
                          for (final p in _pcs)
                            DropdownMenuItem(value: p['id'] as String, child: Text('${p['nama']}', overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => setState(() {
                          _selectedId = v;
                          _pw.clear();
                          _pw2.clear();
                        }),
                      )
                    else if (_admins.isEmpty)
                      const InputDecorator(
                        decoration: InputDecoration(labelText: 'TL / Trainer / PIC NKA'),
                        child: Text('Belum tersedia'),
                      )
                    else
                      DropdownButtonFormField<String>(
                        initialValue: _admin?['id'] as String?,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Nama TL / Trainer / PIC NKA'),
                        items: [
                          for (final p in _admins)
                            DropdownMenuItem(
                              value: p['id'] as String,
                              child: Text(_atasanLabel(p), overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (v) => setState(() {
                          _adminId = v;
                          _pw.clear();
                          _pw2.clear();
                        }),
                      ),
                    if (sel != null && sel['role'] == 'pc') ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        const Icon(Icons.store, size: 18),
                        const SizedBox(width: 6),
                        Expanded(child: Text('${sel['toko']} · ${sel['area']}')),
                      ]),
                    ],
                    if (_needCreate) ...[
                      const SizedBox(height: 12),
                      const InfoBanner('Login pertama: buat password kamu (minimal 6 karakter).', icon: Icons.key),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pw,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: _needCreate ? 'Buat password' : 'Password',
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    if (_needCreate) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pw2,
                        obscureText: _obscure,
                        decoration: const InputDecoration(labelText: 'Ketik ulang password'),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _busy ? null : _submit,
                      icon: busyIcon(_busy, Icons.login),
                      label: Text(_needCreate ? 'Buat password & masuk' : 'Masuk'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    ),
                    const SizedBox(height: 12),
                    if (sel == null || sel['role'] != 'pic' || sel['jabatan'] != null)
                      Text(
                        'Lupa password? Minta Trainer atau PIC NKA melakukan reset.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ]),
      ),
    );
  }
}
