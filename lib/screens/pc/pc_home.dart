import 'package:flutter/material.dart';

import '../../services/notif_service.dart';
import '../../services/pc_sync.dart';
import '../../services/session.dart';
import '../../services/update_service.dart';
import '../../widgets/break_bar.dart';
import 'account_screen.dart';
import 'activity_screen.dart';
import 'contact_detail.dart';
import 'daily_report_screen.dart';
import 'database_screen.dart';
import 'report_screen.dart';

/// Rumah PC: 3 modul (Database, Report, Activity) + Akun.
/// Dipakai juga oleh admin untuk melihat detail PC ([adminView] = true).
class PcHome extends StatefulWidget {
  final Profile pc;
  final bool adminView;
  final int initialTab;

  const PcHome({super.key, required this.pc, this.adminView = false, this.initialTab = 0});

  @override
  State<PcHome> createState() => _PcHomeState();
}

class _PcHomeState extends State<PcHome> {
  late int _tab = widget.initialTab;
  final _dbKey = GlobalKey<DatabaseScreenState>();

  @override
  void initState() {
    super.initState();
    if (!widget.adminView) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) UpdateService.check(context);
      });
      NotifService.requestPermission();
      PcSync.refresh();
      NotifService.onTapListener = _handlePayload;
      final p = NotifService.takePending();
      if (p != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _handlePayload(p));
      }
    }
  }

  @override
  void dispose() {
    if (!widget.adminView) NotifService.onTapListener = null;
    super.dispose();
  }

  void _handlePayload(String? p) {
    if (p == null || !mounted) return;
    if (p == 'laporan') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => DailyReportScreen(pc: widget.pc)));
    } else if (p == 'report') {
      setState(() => _tab = 1);
    } else if (p == 'followup') {
      setState(() => _tab = 0);
      _dbKey.currentState?.showToday();
    } else if (p.startsWith('contact:')) {
      setState(() => _tab = 0);
      final id = p.substring('contact:'.length);
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ContactDetail(pc: widget.pc, contactId: id),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DatabaseScreen(key: _dbKey, pc: widget.pc, adminView: widget.adminView),
      ReportScreen(pc: widget.pc, adminView: widget.adminView),
      ActivityScreen(pc: widget.pc, adminView: widget.adminView),
      if (!widget.adminView) const AccountScreen(),
    ];
    final destinations = <NavigationDestination>[
      const NavigationDestination(icon: Icon(Icons.contacts_outlined), selectedIcon: Icon(Icons.contacts), label: 'Database'),
      const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Report'),
      const NavigationDestination(icon: Icon(Icons.campaign_outlined), selectedIcon: Icon(Icons.campaign), label: 'Activity'),
      if (!widget.adminView)
        const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Akun'),
    ];
    final tab = _tab.clamp(0, pages.length - 1);
    return Scaffold(
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        if (!widget.adminView) BreakBar(pc: widget.pc),
        NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: destinations,
        ),
      ]),
    );
  }
}
