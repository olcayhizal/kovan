import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

// KOVAN: one place that lists every macOS permission the app needs, shows
// whether it is granted, and opens the exact System Settings pane to fix it.

const _kGranted = Color(0xFF1F9D55);
const _kMissing = Color(0xFFC2410C);
const _kSettingsUrl =
    'x-apple.systempreferences:com.apple.preference.security?';

class _MacPermission {
  final String name;
  final String reason;
  final String pane;
  final bool Function(bool prompt) check;
  final bool incoming;

  /// macOS caches this answer per process; only a relaunch picks up a grant.
  final bool needsRestart;

  const _MacPermission(
      this.name, this.reason, this.pane, this.check, this.incoming,
      {this.needsRestart = false});
}

final _permissions = [
  _MacPermission('kovan_perm_screen', 'kovan_perm_screen_tip',
      'Privacy_ScreenCapture', (p) => bind.mainIsCanScreenRecording(prompt: p),
      true,
      needsRestart: true),
  _MacPermission('kovan_perm_acc', 'kovan_perm_acc_tip', 'Privacy_Accessibility',
      (p) => bind.mainIsProcessTrusted(prompt: p), true),
  _MacPermission('kovan_perm_input', 'kovan_perm_input_tip',
      'Privacy_ListenEvent', (p) => bind.mainIsCanInputMonitoring(prompt: p),
      false),
];

class KovanMacPermissions extends StatefulWidget {
  /// Home pane variant: rendered only while something is missing.
  final bool compact;

  const KovanMacPermissions({Key? key, this.compact = false}) : super(key: key);

  @override
  State<KovanMacPermissions> createState() => _KovanMacPermissionsState();
}

class _KovanMacPermissionsState extends State<KovanMacPermissions> {
  late final List<_MacPermission> _items;
  Map<String, bool> _granted = {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final outgoingOnly = bind.isOutgoingOnly();
    _items = _permissions.where((e) => !(outgoingOnly && e.incoming)).toList();
    _refresh();
    // The user flips switches in System Settings, so poll while visible.
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    final next = {for (final e in _items) e.name: e.check(false)};
    if (!mounted) return;
    if (next.length != _granted.length ||
        next.entries.any((e) => _granted[e.key] != e.value)) {
      setState(() => _granted = next);
    }
  }

  Future<void> _open(_MacPermission p) async {
    // Adds KOVAN to the list on first use; macOS prompts only once per app,
    // so the pane is opened as well.
    p.check(true);
    await launchUrl(Uri.parse('$_kSettingsUrl${p.pane}'));
  }

  Future<void> _restart() async {
    // .../KOVAN.app/Contents/MacOS/KOVAN -> .../KOVAN.app
    final app = File(Platform.resolvedExecutable).parent.parent.parent.path;
    await Process.start(
        '/bin/sh', ['-c', 'sleep 1; /usr/bin/open -n "\$0"', app],
        mode: ProcessStartMode.detached);
    exit(0);
  }

  int get _missingCount => _granted.values.where((v) => !v).length;

  @override
  Widget build(BuildContext context) {
    if (widget.compact && _missingCount == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color?.withOpacity(0.75);

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, size: 18, color: MyTheme.accent)
            .marginOnly(top: 1),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(translate('kovan_perm_title'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              _summary(),
            ],
          ),
        ),
      ],
    );

    return Container(
      margin: widget.compact
          ? const EdgeInsets.fromLTRB(12, 20, 12, 16)
          : null,
      padding: widget.compact ? const EdgeInsets.all(14) : null,
      decoration: widget.compact
          ? BoxDecoration(
              color: theme.cardColor,
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.compact) header,
          if (_missingCount > 0)
            Text(translate('kovan_perm_tip'),
                    style: TextStyle(fontSize: 13, height: 1.4, color: muted))
                .marginOnly(top: widget.compact ? 8 : 0, bottom: 4),
          ..._items.map((p) => _row(p, muted)),
          if (_missingCount > 0)
            Text(translate('kovan_perm_auto'),
                    style: TextStyle(fontSize: 13, height: 1.4, color: muted))
                .marginOnly(top: 8),
        ],
      ),
    );
  }

  Widget _summary() {
    final missing = _missingCount;
    final color = missing == 0 ? _kGranted : _kMissing;
    final text = missing == 0
        ? translate('kovan_perm_all_ok')
        : translate('kovan_perm_missing').replaceAll('{}', '$missing');
    return Text(text,
        style:
            TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color));
  }

  Widget _row(_MacPermission p, Color? muted) {
    final granted = _granted[p.name] ?? false;
    final status = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(granted ? Icons.check_circle : Icons.error_outline,
                size: 18, color: granted ? _kGranted : _kMissing)
            .marginOnly(top: 1),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(translate(p.name),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              Text(
                granted
                    ? translate('kovan_perm_granted')
                    : translate(p.reason),
                style: TextStyle(fontSize: 13, height: 1.35, color: muted),
              ),
            ],
          ),
        ),
      ],
    );
    final button = OutlinedButton.icon(
      onPressed: () => _open(p),
      icon: const Icon(Icons.open_in_new, size: 16),
      label: Text(translate('kovan_perm_open')),
      style: OutlinedButton.styleFrom(
        foregroundColor: MyTheme.accent,
        side: BorderSide(color: MyTheme.accent50),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );

    final restart = p.needsRestart
        ? TextButton.icon(
            onPressed: _restart,
            icon: const Icon(Icons.restart_alt, size: 16),
            label: Text(translate('kovan_perm_restart')),
            style: TextButton.styleFrom(
              foregroundColor: MyTheme.accent,
              textStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          )
        : null;

    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 360;
      if (granted) return status.marginOnly(top: 12);
      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            status,
            const SizedBox(height: 8),
            button,
            if (restart != null) restart.marginOnly(top: 4),
          ],
        ).marginOnly(top: 12);
      }
      return Row(
        children: [
          Expanded(child: status),
          const SizedBox(width: 12),
          if (restart != null) restart.marginOnly(right: 8),
          button
        ],
      ).marginOnly(top: 12);
    });
  }
}
