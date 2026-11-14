import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../services/session.dart';
import 'widgets.dart';

/// Foto profil bulat; jika belum ada foto, tampil huruf depan nama.
class AvatarProfil extends StatelessWidget {
  final String? url;
  final String nama;
  final double radius;
  const AvatarProfil({super.key, required this.url, required this.nama, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final huruf = nama.trim().isEmpty ? '?' : nama.trim()[0].toUpperCase();
    final u = url;
    if (u == null || u.isEmpty) {
      return CircleAvatar(radius: radius, child: Text(huruf, style: TextStyle(fontSize: radius * 0.85)));
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey.shade300,
      backgroundImage: NetworkImage(u),
      onBackgroundImageError: (_, __) {},
    );
  }
}

/// Ganti foto profil akun yang sedang login: pilih kamera / galeri, unggah ke bucket "profil".
Future<void> gantiFotoProfil(BuildContext context) async {
  final me = Session.current;
  if (me == null) return;
  final sumber = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AvatarProfil(url: me.fotoUrl, nama: me.nama, radius: 44),
        ),
        ListTile(
          leading: const Icon(Icons.photo_camera),
          title: const Text('Ambil foto dari kamera'),
          onTap: () => Navigator.pop(ctx, 'kamera'),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library),
          title: const Text('Pilih dari galeri'),
          onTap: () => Navigator.pop(ctx, 'galeri'),
        ),
        if (me.fotoUrl != null)
          ListTile(
            leading: Icon(Icons.delete_outline, color: Colors.red.shade700),
            title: Text('Hapus foto profil', style: TextStyle(color: Colors.red.shade700)),
            onTap: () => Navigator.pop(ctx, 'hapus'),
          ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (sumber == null) return;
  try {
    if (sumber == 'hapus') {
      await Session.db.rpc('set_foto_profil', params: {'p_url': null});
    } else {
      final x = await ImagePicker().pickImage(
        source: sumber == 'kamera' ? ImageSource.camera : ImageSource.gallery,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final path = '${me.id}/foto.jpg';
      await Session.db.storage.from('profil').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
      final url = '${Session.db.storage.from('profil').getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
      await Session.db.rpc('set_foto_profil', params: {'p_url': url});
    }
    await Session.load();
    Session.perubahan.value++;
    if (context.mounted) showMsg(context, sumber == 'hapus' ? 'Foto profil dihapus' : 'Foto profil diperbarui');
  } catch (e) {
    if (context.mounted) showErr(context, e);
  }
}
