import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/app_info.dart';
import '../state/auth_service.dart';
import '../state/browsing_mode_service.dart';
import '../state/locale_service.dart';
import '../state/store_config_service.dart';
import '../widgets/dev_tool_cards.dart';
import '../widgets/profile_sheet.dart';
import '../widgets/server_connection_panel.dart';

/// Version, build and session details as plain text, for the Settings
/// header popup and for pasting into a bug report.
String sessionInfoText() {
  final username = authService.username ?? '—';
  final storeSlug = storeConfigService.storeSlug ?? '—';
  final host = AppConfig.apiBaseUrlLabel;
  final mode = browsingModeService.mode.name;
  final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
  final screen = view == null
      ? '—'
      : '${view.physicalSize.width.round()}x${view.physicalSize.height.round()} px '
          '@ ${view.devicePixelRatio.toStringAsFixed(2)}x = '
          '${(view.physicalSize.width / view.devicePixelRatio).round()}x'
          '${(view.physicalSize.height / view.devicePixelRatio).round()} dp';
  return 'user:    $username\n'
      'store:   $storeSlug\n'
      'host:    $host\n'
      'mode:    $mode\n'
      'screen:  $screen\n'
      'version: ${AppInfo.version}\n'
      'build:   ${AppInfo.buildNumber}\n'
      'built:   ${AppInfo.buildTime}';
}

Future<void> showSessionInfoDialog(BuildContext context) async {
  final text = sessionInfoText();
  var copied = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Session info'),
        content: SingleChildScrollView(
          child: SelectableText(
            text,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              setDialogState(() => copied = true);
            },
            child: Text(copied ? 'Copied' : 'Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );
}

/// Customer-app Settings: language, server connection, account, app
/// version. The kiosk app this was forked from had a much larger Settings
/// screen (device identity, payment terminal diagnostics, idle timers,
/// auto-restart, a simulator) — none of that applies to a customer's own
/// browser/phone/computer, so this is a from-scratch, much smaller screen.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = context.watch<LocaleService>().locale;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          // Same profile sheet as the home screen's person icon.
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: l10n.profileTitle,
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (_) => const ProfileSheet(),
            ),
          ),
          // Circular "!" — version, build and session info at a glance.
          IconButton(
            icon: const Icon(Icons.error_outline),
            tooltip: 'Session info',
            onPressed: () => showSessionInfoDialog(context),
          ),
        ],
      ),
      // Same section pattern as the kiosk Settings (title, control, divider,
      // grouped cards), in a centered column so it doesn't stretch across a
      // desktop or tablet window.
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Language ────────────────────────────────────────────────
            Text(l10n.settingsLanguage,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            SegmentedButton<Locale>(
              segments: const [
                ButtonSegment(value: Locale('en'), label: Text('English')),
                ButtonSegment(value: Locale('ar'), label: Text('العربية')),
              ],
              selected: {locale},
              onSelectionChanged: (sel) => localeService.setLocale(sel.first),
            ),
            const Divider(height: 40),
            const ServerConnectionPanel(),
            const SizedBox(height: 12),
            const DeveloperToolsCard(),
            const SizedBox(height: 12),
            const SimulatorsCard(),
            const SizedBox(height: 12),
            const ScanOptionsCard(),
            const SizedBox(height: 12),
            const LandingPagesCard(),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'waha_client ${AppInfo.version} (${AppInfo.buildNumber})',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
          ],
            ),
          ),
        ),
      ),
    );
  }
}
