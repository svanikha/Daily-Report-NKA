import 'package:flutter/material.dart';

import '../data/nka.dart';
import '../services/session.dart';
import '../utils.dart';

/// Timegone: tanggal / jumlah hari di bulan itu (10/30 = 33%).
class TimegoneBar extends StatelessWidget {
  final HariKerja hk;

  /// Tampilkan sisa hari kerja (khusus toko/PC; TL/PIC cukup timegone).
  final bool tampilSisa;
  const TimegoneBar({super.key, required this.hk, this.tampilSisa = true});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.hourglass_bottom, color: c),
            const SizedBox(width: 8),
            const Expanded(child: Text('Timegone', style: TextStyle(fontWeight: FontWeight.bold))),
            Text(hk.timegoneText, style: TextStyle(fontWeight: FontWeight.bold, color: c)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: hk.timegone / 100, minHeight: 6, color: c, backgroundColor: Colors.grey.shade200),
          ),
          if (tampilSisa) ...[
            const SizedBox(height: 6),
            Text(
              'Sisa hari kerja: ${hk.sisaHariKerja} hari'
              '${hk.offdaySisa > 0 ? ' (sisa ${hk.totalHari - hk.hariKe + 1} hari dikurangi ${hk.offdaySisa} offday)' : ' (termasuk hari ini)'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ]),
      ),
    );
  }
}

/// Rupiah ringkas untuk kartu: Rp45,2 jt / Rp1,25 M.
String rupiahSingkat(num v) {
  final a = v.abs();
  String f(double x, int d) => x.toStringAsFixed(d).replaceAll('.', ',').replaceAll(RegExp(r',0+$'), '');
  if (a >= 1e9) return 'Rp${f(v / 1e9, 2)} M';
  if (a >= 1e6) return 'Rp${f(v / 1e6, 1)} jt';
  return rupiah(v);
}

/// Ringkasan sell-out: kotak-kotak capaian (unit HP, value HP, tipe fokus, IoT) dengan
/// persentase target (hijau jika di atas timegone), tambahan hari ini, dan kebutuhan per hari kerja.
class SellOutCard extends StatelessWidget {
  final Map<String, dynamic> hari;
  final Map<String, dynamic> bulan;
  final Map<String, dynamic> target;
  final HariKerja hk;

  /// Judul tambahan, misal "Semua toko area Sampit".
  final String? judul;

  /// Ketuk kotak HP / IoT (misal membuka riwayat penjualan).
  final VoidCallback? onTapHp;
  final VoidCallback? onTapIot;
  const SellOutCard(
      {super.key,
      required this.hari,
      required this.bulan,
      required this.target,
      required this.hk,
      this.judul,
      this.onTapHp,
      this.onTapIot});

  @override
  Widget build(BuildContext context) {
    String unit(num v) => '${angka(v)} unit';
    return Column(children: [
      _section(
        context,
        'SELL OUT HP',
        Icons.smartphone,
        'Hari ini ${angka(toNum(hari['unit']))} unit · ${rupiahSingkat(toNum(hari['value']))}',
        [
          _Metrik('Unit HP', toNum(bulan['unit']), toNum(target['unit']), toNum(hari['unit']), unit, hk, onTap: onTapHp),
          _Metrik('Value HP', toNum(bulan['value']), toNum(target['value']), toNum(hari['value']), rupiahSingkat, hk, onTap: onTapHp),
          _Metrik('Fokus A7 Pro', toNum(bulan['fokus_a7pro']), toNum(target['fokus_a7pro']), toNum(hari['fokus_a7pro']),
              unit, hk),
          _Metrik('Fokus Reno 16', toNum(bulan['fokus_reno16']), toNum(target['fokus_reno16']),
              toNum(hari['fokus_reno16']), unit, hk),
        ],
      ),
      _section(
        context,
        'SELL OUT IoT',
        Icons.watch,
        'Hari ini ${angka(toNum(hari['iot']))} unit · ${rupiahSingkat(toNum(hari['iot_value']))}',
        [
          _Metrik('Unit IoT', toNum(bulan['iot']), toNum(target['iot']), toNum(hari['iot']), unit, hk, onTap: onTapIot),
          _Metrik('Value IoT', toNum(bulan['iot_value']), 0, toNum(hari['iot_value']), rupiahSingkat, hk, onTap: onTapIot),
        ],
      ),
    ]);
  }

  Widget _section(BuildContext context, String title, IconData icon, String sub, List<_Metrik> tiles) {
    final c = Theme.of(context).colorScheme.primary;
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: tiles[i]),
            const SizedBox(width: 8),
            Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
          ]),
        ),
      ));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: c),
            const SizedBox(width: 6),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            if (judul != null) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text('· $judul', overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          ]),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ...rows,
        ]),
      ),
    );
  }
}

/// Satu kotak capaian.
class _Metrik extends StatelessWidget {
  final String label;
  final num capai;
  final num target;
  final num hariIni;
  final String Function(num) fmt;
  final HariKerja hk;
  final VoidCallback? onTap;
  const _Metrik(this.label, this.capai, this.target, this.hariIni, this.fmt, this.hk, {this.onTap});

  @override
  Widget build(BuildContext context) {
    final adaTarget = target > 0;
    final p = adaTarget ? capai / target * 100 : 0.0;
    final aman = p >= hk.timegone;
    final c = !adaTarget ? Colors.blueGrey : (aman ? Colors.green.shade700 : Colors.red.shade700);

    String bawah;
    Color warnaBawah;
    if (!adaTarget) {
      bawah = 'Target belum diatur';
      warnaBawah = Colors.grey.shade600;
    } else if (capai >= target) {
      bawah = 'Target tercapai ✓';
      warnaBawah = Colors.green.shade700;
    } else if (hk.sisaHariKerja <= 0) {
      bawah = 'Kurang ${fmt(target - capai)}';
      warnaBawah = Colors.red.shade700;
    } else {
      final ph = hk.perHari(target, capai);
      bawah = 'Perlu ${fmt(ph.ceil())}/hari';
      warnaBawah = aman ? Colors.green.shade700 : Colors.red.shade700;
    }

    final kotak = _kotak(c, adaTarget, p, bawah, warnaBawah);
    if (onTap == null) return kotak;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(10), onTap: onTap, child: kotak),
    );
  }

  Widget _kotak(Color c, bool adaTarget, double p, String bawah, Color warnaBawah) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade800, fontWeight: FontWeight.w600)),
          ),
          if (adaTarget)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)),
              child: Text('${p.toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
        ]),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(fmt(capai), style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: c)),
        ),
        Text(adaTarget ? 'dari ${fmt(target)}' : 'bulan ini',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: adaTarget ? (p / 100).clamp(0.0, 1.0).toDouble() : 0,
            minHeight: 5,
            color: c,
            backgroundColor: Colors.grey.shade200,
          ),
        ),
        const SizedBox(height: 5),
        Text(bawah, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: warnaBawah)),
        if (hariIni > 0)
          Text('+${fmt(hariIni)} hari ini', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
        if (onTap != null)
          Text('Ketuk untuk riwayat ›', style: TextStyle(fontSize: 10.5, color: c, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Dashboard atasan: memuat ringkasan sell out (RPC ringkasan_sellout) untuk satu toko atau
/// semua toko di cakupan akun, lalu menampilkannya dengan SellOutCard.
class RingkasanSellOut extends StatefulWidget {
  final int? storeId;
  final DateTime tanggal;
  final String? judul;

  /// Ditampilkan jika fungsi server belum tersedia.
  final Widget? cadangan;

  /// Berubah setiap halaman induk memuat ulang: data dimuat ulang tanpa berkedip.
  final int rev;
  const RingkasanSellOut(
      {super.key, required this.storeId, required this.tanggal, this.judul, this.cadangan, this.rev = 0});

  @override
  State<RingkasanSellOut> createState() => _RingkasanSellOutState();
}

class _RingkasanSellOutState extends State<RingkasanSellOut> {
  Map<String, dynamic>? _r;
  bool _gagal = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RingkasanSellOut old) {
    super.didUpdateWidget(old);
    if (old.rev != widget.rev) _load();
  }

  Future<void> _load() async {
    try {
      final r = asMap(await Session.db
          .rpc('ringkasan_sellout', params: {'p_store': widget.storeId, 'p_tanggal': ymd(widget.tanggal)}));
      if (mounted) setState(() => _r = r);
    } catch (_) {
      if (mounted) setState(() => _gagal = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_gagal) return widget.cadangan ?? const SizedBox.shrink();
    final r = _r;
    if (r == null) return const Card(child: Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()));
    return SellOutCard(
      hari: asMap(r['hari']),
      bulan: asMap(r['bulan']),
      target: asMap(r['target']),
      hk: HariKerja.dari(widget.tanggal),
      judul: widget.judul,
    );
  }
}
