import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String errMsg(Object e) {
  if (e is PostgrestException) {
    if (e.message.contains('row-level security')) {
      return 'Tidak diizinkan. PC hanya bisa input hari ini sebelum 22.00 WIB; TL/Trainer hanya untuk toko non PC, PC offday, atau PC yang tidak lapor.';
    }
    return e.message;
  }
  if (e is AuthException) return e.message;
  if (e is StorageException) return e.message;
  if (e is String) return e;
  final s = e.toString();
  if (s.contains('SocketException') || s.contains('ClientException')) {
    return 'Tidak ada koneksi internet. Coba lagi.';
  }
  return s;
}

void showMsg(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

void showErr(BuildContext context, Object e) => showMsg(context, errMsg(e));

Future<bool> confirmDialog(BuildContext context, String title, String message, {String yes = 'Ya'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
      ],
    ),
  );
  return r ?? false;
}

Color pctColor(double p) {
  if (p >= 100) return Colors.green.shade700;
  if (p >= 70) return Colors.orange.shade800;
  return Colors.red.shade700;
}

Color statusColor(String? s) {
  switch (s) {
    case 'Asking':
      return Colors.blue.shade700;
    case 'Probing':
      return Colors.orange.shade800;
    case 'Closing':
      return Colors.green.shade700;
    default:
      return Colors.grey.shade700;
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, {super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) => Pill(status, color: statusColor(status));
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final IconData icon;
  final Color? color;

  const StatCard({super.key, required this.label, required this.value, this.sub, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    final t = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: c),
            const SizedBox(width: 6),
            Expanded(child: Text(label, style: t.labelMedium, maxLines: 2)),
          ]),
          const SizedBox(height: 8),
          Text(value, style: t.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          if (sub != null) Text(sub!, style: t.bodySmall),
        ]),
      ),
    );
  }
}

/// Grid 2 kolom untuk StatCard.
class StatGrid extends StatelessWidget {
  final List<Widget> children;
  const StatGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      // HP: 2 kolom. Laptop: 3-4 kolom.
      final cols = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 700 ? 3 : 2);
      final w = (c.maxWidth - 8 * (cols - 1)) / cols;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    });
  }
}

class ProgressTile extends StatelessWidget {
  final String label;
  final num actual;
  final num target;
  final String Function(num) fmt;
  final String? extra;

  const ProgressTile({
    super.key,
    required this.label,
    required this.actual,
    required this.target,
    required this.fmt,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final double p = target > 0 ? actual / target * 100 : 0;
    final hasTarget = target > 0;
    final extraText = extra != null ? ' · $extra' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(hasTarget ? '${fmt(actual)} / ${fmt(target)}' : fmt(actual)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: hasTarget ? (p / 100).clamp(0.0, 1.0) : 0,
            minHeight: 6,
            color: hasTarget ? pctColor(p) : Colors.grey,
            backgroundColor: Colors.grey.shade200,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          hasTarget ? '${p.toStringAsFixed(0)}% dari target$extraText' : 'Target belum diatur$extraText',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: hasTarget ? pctColor(p) : null),
        ),
      ]),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionHeader(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Row(children: [
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String text;
  final IconData icon;
  const EmptyState({super.key, required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(children: [
        Icon(icon, size: 40, color: Colors.grey.shade400),
        const SizedBox(height: 8),
        Text(text, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
      ]),
    );
  }
}

class ErrorRetry extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const ErrorRetry({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(error, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Coba lagi')),
        ]),
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  const InfoBanner(this.text, {super.key, this.icon = Icons.info_outline, this.color = Colors.blueGrey});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: color))),
      ]),
    );
  }
}

Widget busyIcon(bool busy, IconData icon) => busy
    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
    : Icon(icon);

