import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:async';

import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/api_client.dart';
import '../state/auth_service.dart';
import '../state/browsing_mode_service.dart';
import '../state/startup_connection.dart';

/// Blocks the app behind a "Connecting…" card while the server is
/// unreachable at startup (see [StartupConnection]). Sits above the Navigator
/// on purpose so it covers every route; it needs no Overlay of its own.
class ConnectionGateOverlay extends StatelessWidget {
  final Widget child;
  const ConnectionGateOverlay({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable:
          Listenable.merge([startupConnection, authService, browsingModeService]),
      builder: (context, _) {
        final show = startupConnection.active && !startupConnection.suspended;
        // Shopping mode always runs on an account (a regular one or the
        // automatic guest). With none, nothing behind this card may be used
        // until one exists.
        final needsSession = !startupConnection.active &&
            browsingModeService.mode == BrowsingMode.shopping &&
            !authService.isLoggedIn;
        return Stack(
          children: [
            child,
            if (show) const Positioned.fill(child: _GateCard()),
            if (needsSession) const Positioned.fill(child: _SessionGateCard()),
          ],
        );
      },
    );
  }
}

class _GateCard extends StatefulWidget {
  const _GateCard();

  @override
  State<_GateCard> createState() => _GateCardState();
}

class _GateCardState extends State<_GateCard> {
  // Hidden way in: 15 quick taps on the title, each within 1 s of the last.
  static const _tapsNeeded = 15;
  static const _maxGap = Duration(seconds: 1);
  int _taps = 0;
  DateTime? _last;

  void _onTitleTap() {
    final now = DateTime.now();
    _taps =
        (_last != null && now.difference(_last!) <= _maxGap) ? _taps + 1 : 1;
    _last = now;
    if (_taps >= _tapsNeeded) {
      _taps = 0;
      startupConnection.openConnectionScreen();
    }
  }

  void _showDetails(BuildContext context) {
    final text = startupConnection.details;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connection details'),
        content: SingleChildScrollView(
          child: SelectableText(text,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: text)),
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final custom = AppConfig.isCustomConnectionActive;

    // Listens on its own: the overlay above hands us a const widget, which
    // Flutter would never rebuild when the countdown changes.
    return ListenableBuilder(
      listenable: startupConnection,
      builder: (context, _) {
        final s = startupConnection;
        return Material(
          color: Colors.black54,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _onTitleTap,
                        child: Row(
                          children: [
                            if (s.probing)
                              const SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2.5),
                              )
                            else
                              Icon(Icons.cloud_off,
                                  size: 22, color: scheme.error),
                            const SizedBox(width: 12),
                            Text(
                              s.probing
                                  ? 'Connecting to server…'
                                  : 'Connection failed',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        AppConfig.apiBaseUrl,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      if (s.probing) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 10),
                        Text(
                          'Attempt ${s.attempt + 1} — trying now…',
                          style: TextStyle(fontSize: 12, color: scheme.outline),
                        ),
                      ] else ...[
                        Text(s.shortError,
                            style:
                                TextStyle(fontSize: 13, color: scheme.error)),
                        const SizedBox(height: 6),
                        Text(
                          'Attempt ${s.attempt} failed — Retrying in ${s.secondsLeft}s',
                          style: TextStyle(fontSize: 12, color: scheme.outline),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            onPressed: s.probing ? null : s.retryNow,
                            child: const Text('Retry now'),
                          ),
                          OutlinedButton(
                            onPressed: () => _showDetails(context),
                            child: const Text('Details'),
                          ),
                          if (custom) ...[
                            OutlinedButton(
                              onPressed: () => s.openConnectionScreen(),
                              child: const Text('Edit connection'),
                            ),
                            OutlinedButton(
                              onPressed: () =>
                                  s.openConnectionScreen(customOn: false),
                              child: const Text('Use project default'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Shown in shopping mode while no session exists (the guest account could
/// not be created at startup). Keeps trying on its own and has a button to
/// try right away; disappears as soon as a session exists.
class _SessionGateCard extends StatefulWidget {
  const _SessionGateCard();

  @override
  State<_SessionGateCard> createState() => _SessionGateCardState();
}

class _SessionGateCardState extends State<_SessionGateCard> {
  Timer? _timer;
  bool _trying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _try());
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _try());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _try() async {
    if (_trying || !mounted) return;
    setState(() => _trying = true);
    try {
      final api = context.read<ApiClient>();
      await authService.loginAsGuest(api);
      await authService.resolveDefaultStore(api);
    } catch (_) {
      // Still no server or session: the timer tries again.
    }
    if (mounted) setState(() => _trying = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: Colors.black54,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(l10n.sessionStartingTitle,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(l10n.sessionStartingHint, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _trying ? null : _try,
                    child: Text(l10n.sessionRetry),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
