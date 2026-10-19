import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../router/app_router.dart';
import '../services/app_info.dart';
import '../state/auth_service.dart';
import '../state/locale_service.dart';
import '../widgets/server_connection_panel.dart';

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
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.language_outlined),
                title: Text(l10n.settingsLanguage),
                trailing: DropdownButton<Locale>(
                  value: locale,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: Locale('en'), child: Text('English')),
                    DropdownMenuItem(value: Locale('ar'), child: Text('العربية')),
                  ],
                  onChanged: (v) {
                    if (v != null) localeService.setLocale(v);
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (authService.isLoggedIn)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(authService.username ?? 'Account'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).pushNamed(Routes.profile),
                ),
              )
            else
              Card(
                child: ListTile(
                  leading: const Icon(Icons.login),
                  title: const Text('Sign in'),
                  onTap: () => Navigator.of(context).pushNamed(Routes.login),
                ),
              ),
            const SizedBox(height: 12),
            const ServerConnectionPanel(),
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
    );
  }
}
