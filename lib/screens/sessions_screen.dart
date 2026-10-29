import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/api_client.dart';
import '../services/api_exceptions.dart';
import '../state/auth_service.dart';

/// The signed-in user's own sessions (phones, browsers, computers), with
/// "sign out" per device and "sign out other devices".
class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  List<Map<String, dynamic>>? _items;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final t = authService.token;
    if (t == null) return;
    try {
      final items = await api.mySessions(t);
      if (mounted) setState(() => _items = items);
    } on UnauthorizedException {
      if (mounted) Navigator.of(context).pop();
    } on UnknownApiException catch (e) {
      final l10n = AppLocalizations.of(context)!;
      if (mounted) {
        setState(() => _error =
            e.statusCode == 404 ? l10n.sessionsUnavailable : e.message);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _run(Future<void> Function(ApiClient, String) action) async {
    final api = context.read<ApiClient>();
    final t = authService.token;
    if (t == null) return;
    setState(() => _busy = true);
    try {
      await action(api, t);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _title(Map<String, dynamic> s) {
    final info = s['info'] as Map<String, dynamic>?;
    final parts = <String>[
      if (info?['model'] != null) '${info!['model']}',
      if (info?['browser'] != null) '${info!['browser']}',
      if (info?['os'] != null)
        '${info!['os']}${info['osVersion'] != null ? ' ${info['osVersion']}' : ''}',
    ];
    return parts.isEmpty ? 'Unknown device' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = _items;
    final hasOthers = items?.any((s) => s['current'] != true) ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.sessionsTitle)),
      body: SafeArea(
        child: _error != null
            ? Center(child: Padding(
                padding: const EdgeInsets.all(24), child: Text(_error!)))
            : items == null
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? Center(child: Text(l10n.sessionsEmpty))
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          for (final s in items)
                            Card(
                              child: ListTile(
                                leading: Icon(s['current'] == true
                                    ? Icons.phone_android
                                    : Icons.devices_other),
                                title: Text(_title(s)),
                                subtitle: Text([
                                  if (s['current'] == true)
                                    l10n.sessionsThisDevice,
                                  if (s['storeName'] != null)
                                    '${s['storeName']}',
                                  if (s['lastSeenAt'] != null)
                                    l10n.sessionsLastSeen(
                                        '${s['lastSeenAt']}'.split('.').first
                                            .replaceFirst('T', ' ')),
                                ].join('\n')),
                                isThreeLine: true,
                                trailing: s['current'] == true
                                    ? null
                                    : TextButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _run((api, t) =>
                                                api.endMySession(
                                                    t, '${s['ref']}')),
                                        child: Text(l10n.sessionsSignOut),
                                      ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          if (hasOthers)
                            FilledButton.tonal(
                              onPressed: _busy
                                  ? null
                                  : () => _run((api, t) async {
                                        await api.signOutOtherSessions(t);
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                                  content: Text(
                                                      l10n.sessionsOthersDone)));
                                        }
                                      }),
                              child: Text(l10n.sessionsSignOutOthers),
                            ),
                        ],
                      ),
      ),
    );
  }
}
