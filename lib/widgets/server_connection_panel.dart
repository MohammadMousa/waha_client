import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../config/connection_settings.dart';
import '../router/app_router.dart';
import '../services/api_client.dart';
import '../services/connection_switcher.dart';
import '../state/auth_service.dart';
import '../state/browsing_mode_service.dart';
import '../state/order_flow_controller.dart';

/// Lets the app point at a different server (or back to the project
/// default) and, if the server requires it, signs in while switching.
/// Shown as its own screen before login (see ServerConnectionScreen) and,
/// in the kiosk app this was forked from, also as a card inside Settings —
/// kept exactly as-is here, just moved out of the deleted Settings screen
/// since this is the one piece of it every mode still needs.
enum _ServerPreset {
  emulator('Emulator — 10.0.2.2', 'http', '10.0.2.2', 8081),
  localhost('Localhost (this device)', 'http', '127.0.0.1', 8081),
  lan('LAN — 192.168.1.x', 'http', '192.168.1.', 8081),
  hospitality('api.hospitalitysourcesllc.com', 'https',
      'api.hospitalitysourcesllc.com', 443),
  waha1('waha1.duckdns.org', 'https', 'waha1.duckdns.org', 443),
  custom('Custom', 'http', '', 8081);

  final String label;
  final String scheme;
  final String host;
  final int port;
  const _ServerPreset(this.label, this.scheme, this.host, this.port);
}

class ServerConnectionPanel extends StatefulWidget {
  /// Open by default — used when the panel is the whole screen (startup
  /// connection popup), rather than one card among other settings.
  final bool initiallyExpanded;

  /// Start with the Custom Connection switch in this position instead of the
  /// saved one (e.g. OFF for "Use project default").
  final bool? initialCustomOn;

  const ServerConnectionPanel(
      {super.key, this.initiallyExpanded = false, this.initialCustomOn});

  @override
  State<ServerConnectionPanel> createState() => _ServerConnectionPanelState();
}

class _ServerConnectionPanelState extends State<ServerConnectionPanel> {
  bool _expanded = false;
  bool _customOn = false;
  bool _showAdvanced = false;
  String _scheme = 'http';
  _ServerPreset _preset = _ServerPreset.custom;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _pathCtrl;
  final _userCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();
  bool _saving = false;
  String? _result;
  bool _resultIsError = false;

  @override
  void initState() {
    super.initState();
    final conn = AppConfig.connection;
    final saved = conn.custom;
    _customOn = widget.initialCustomOn ?? conn.customEnabled;
    _expanded = widget.initiallyExpanded;
    _scheme = saved.scheme;
    // The saved fields are shown as-is, even while Custom is OFF, so they are
    // still there when it is switched back ON.
    _hostCtrl = TextEditingController(text: saved.host);
    _portCtrl = TextEditingController(text: saved.port?.toString() ?? '');
    _pathCtrl = TextEditingController(text: saved.basePath);
    _showAdvanced = saved.basePath.isNotEmpty;
    _detectPreset();
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _pathCtrl.dispose();
    _userCtrl.dispose();
    _secretCtrl.dispose();
    super.dispose();
  }

  int? get _port {
    final t = _portCtrl.text.trim();
    return t.isEmpty ? null : int.tryParse(t);
  }

  /// What the form currently describes — a draft until Save & Apply.
  CustomConnection get _draft => CustomConnection(
        scheme: _scheme,
        host: _hostCtrl.text.trim(),
        port: _port,
        basePath: CustomConnection.normalizeBasePath(_pathCtrl.text),
      );

  /// Null when usable. A non-numeric port isn't caught by [_draft.validate]
  /// (it parses to null = "no port"), so check it here.
  String? get _draftError {
    final t = _portCtrl.text.trim();
    if (t.isNotEmpty && int.tryParse(t) == null) return 'Port must be a number';
    return _draft.validate();
  }

  void _detectPreset() {
    final host = _hostCtrl.text.trim();
    final port = _port;
    for (final p in _ServerPreset.values) {
      if (p == _ServerPreset.custom || p == _ServerPreset.lan) continue;
      if (p.host == host && p.port == port && p.scheme == _scheme) {
        _preset = p;
        return;
      }
    }
    _preset = host.startsWith('192.168.1.') && _scheme == 'http'
        ? _ServerPreset.lan
        : _ServerPreset.custom;
  }

  void _selectPreset(_ServerPreset p) {
    setState(() {
      _preset = p;
      if (p == _ServerPreset.custom) return;
      _scheme = p.scheme;
      _hostCtrl.text = p.host;
      _portCtrl.text = p.port.toString();
      // Leave the cursor at the end so the last LAN octet can be typed.
      _hostCtrl.selection =
          TextSelection.collapsed(offset: _hostCtrl.text.length);
    });
  }

  /// The switch only moves the draft. Nothing changes on the device until
  /// the Apply button succeeds — going either way means signing in to a
  /// server, so it has to be tested first.
  void _toggleCustom(bool on) => setState(() {
        _customOn = on;
        _result = null;
      });

  /// True when the button has something to do: Custom draft is ON, or it is
  /// OFF while a custom server is still the active one.
  bool get _needsApply => _customOn || AppConfig.connection.customActive;

  Future<void> _apply() async {
    if (_customOn) {
      final error = _draftError;
      if (error != null) {
        setState(() {
          _resultIsError = true;
          _result = error;
        });
        return;
      }
    }
    final api = context.read<ApiClient>();
    final order = context.read<OrderFlowController>();
    final nav = Navigator.of(context);

    // A cart/order belongs to the server it was made on.
    if (order.cart.isNotEmpty || order.orderId != null) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Discard current cart?'),
          content: const Text(
              'A cart or order is in progress. Switching server discards it.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Switch')),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }

    setState(() {
      _saving = true;
      _result = null;
    });
    final result = await ConnectionSwitcher.apply(
      customEnabled: _customOn,
      // OFF keeps whatever custom fields were saved — the form is not saved.
      custom: _customOn ? _draft : AppConfig.connection.custom,
      activeApi: api,
      order: order,
      credentials: _credsNeeded
          ? SwitchCredentials(_userCtrl.text, _secretCtrl.text)
          : null,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _resultIsError = !result.ok;
      _result = result.ok
          ? '✓ ${result.message}'
          : '✗ ${_stepLabel(result.failedStep)}: ${result.message}';
      if (result.ok) {
        _userCtrl.clear();
        _secretCtrl.clear();
      }
    });
    if (result.ok) {
      nav.pushNamedAndRemoveUntil(Routes.landing, (_) => false);
    }
  }

  String _stepLabel(String? step) => switch (step) {
        'address' => 'Address',
        'server' => 'Server',
        _ => 'Sign-in',
      };

  // waha_client has no device-identity (Kiosk) mode — Shopping is a guest
  // account (no credentials), Normal needs username + password.
  bool get _credsNeeded => browsingModeService.mode != BrowsingMode.shopping;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final draftUrl = _draft.url;
    final draftOk = _draftError == null;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.dns_outlined, color: scheme.primary, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Server Connection',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      color: scheme.outline),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: ListenableBuilder(
                listenable: AppConfig.connection,
                builder: (context, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Custom Connection switch (OFF by default) ─────────
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Custom Connection'),
                      subtitle: Text(
                        _customOn
                            ? 'Overrides the app default'
                            : 'Off — using the app default',
                        style: TextStyle(fontSize: 11, color: scheme.outline),
                      ),
                      value: _customOn,
                      onChanged: _saving ? null : _toggleCustom,
                    ),

                    if (!_customOn) ...[
                      const SizedBox(height: 4),
                      Text('Using app default',
                          style:
                              TextStyle(fontSize: 12, color: scheme.outline)),
                      Text(
                        AppConfig.defaultApiBaseUrl,
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: scheme.primary),
                      ),
                    ] else ...[
                      const SizedBox(height: 8),

                      // ── Preset (fills the form, never locks it) ────────
                      _FieldRow(
                        label: 'Preset',
                        child: DropdownButtonFormField<_ServerPreset>(
                          value: _preset,
                          isDense: true,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: _ServerPreset.values
                              .map((p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(p.label),
                                  ))
                              .toList(),
                          onChanged: (p) => _selectPreset(p!),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // ── Scheme ─────────────────────────────────────────
                      _FieldRow(
                        label: 'Scheme',
                        child: DropdownButtonFormField<String>(
                          value: _scheme,
                          isDense: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'http', child: Text('HTTP')),
                            DropdownMenuItem(
                                value: 'https', child: Text('HTTPS')),
                          ],
                          onChanged: (v) => setState(() {
                            _scheme = v!;
                            _detectPreset();
                          }),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // ── Host / IP ──────────────────────────────────────
                      _FieldRow(
                        label: 'Host / IP',
                        child: TextField(
                          controller: _hostCtrl,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                            hintText: 'api.example.com or 192.168.1.x',
                          ),
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          onChanged: (_) => setState(_detectPreset),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // ── Port (optional) ────────────────────────────────
                      _FieldRow(
                        label: 'Port',
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: 120,
                            child: TextField(
                              controller: _portCtrl,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                                hintText: 'optional',
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(_detectPreset),
                            ),
                          ),
                        ),
                      ),

                      // ── Advanced: base path ────────────────────────────
                      InkWell(
                        onTap: () =>
                            setState(() => _showAdvanced = !_showAdvanced),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Text('Advanced',
                                  style: TextStyle(
                                      fontSize: 12, color: scheme.primary)),
                              Icon(
                                  _showAdvanced
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 16,
                                  color: scheme.primary),
                            ],
                          ),
                        ),
                      ),
                      if (_showAdvanced)
                        _FieldRow(
                          label: 'Base path',
                          child: TextField(
                            controller: _pathCtrl,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                              hintText: 'optional, e.g. /waha',
                            ),
                            autocorrect: false,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),

                      // ── URL preview (read-only) ────────────────────────
                      if (draftUrl.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          draftOk ? draftUrl : '$draftUrl  ✗ $_draftError',
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: draftOk ? scheme.primary : scheme.error),
                        ),
                      ],

                      // ── Active indicator ───────────────────────────────
                      if (AppConfig.isCustomConnectionActive) ...[
                        const SizedBox(height: 8),
                        Text('Active:',
                            style:
                                TextStyle(fontSize: 12, color: scheme.outline)),
                        Text(
                          AppConfig.apiBaseUrl,
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                    if (_needsApply) ...[
                      const SizedBox(height: 14),
                      if (_credsNeeded) ...[
                        Text(
                          'Sign in to the ${_customOn ? 'new' : 'default'} server (not saved)',
                          style: TextStyle(fontSize: 12, color: scheme.outline),
                        ),
                        const SizedBox(height: 6),
                        _FieldRow(
                          label: 'User',
                          child: TextField(
                            controller: _userCtrl,
                            decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                isDense: true,
                                hintText: authService.username != null
                                    ? 'optional — ${authService.username}'
                                    : 'username'),
                            autocorrect: false,
                            enableSuggestions: false,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _FieldRow(
                          label: 'Password',
                          child: TextField(
                            controller: _secretCtrl,
                            obscureText: true,
                            enableSuggestions: false,
                            autocorrect: false,
                            decoration: const InputDecoration(
                                border: OutlineInputBorder(), isDense: true),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _saving ? null : _apply,
                          child: _saving
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : Text(_customOn
                                  ? 'Save & Apply'
                                  : 'Use app default'),
                        ),
                      ),
                    ],
                    if (_result != null) ...[
                      const SizedBox(height: 8),
                      Text(_result!,
                          style: TextStyle(
                              fontSize: 12,
                              color: _resultIsError
                                  ? scheme.error
                                  : scheme.outline)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _FieldRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: child),
      ],
    );
  }
}
