import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config/app_config.dart';
import '../services/api_client.dart';
import '../services/landing_cache.dart';
import '../services/local_prefs.dart';
import '../state/auth_service.dart';
import '../state/browsing_mode_service.dart';
import '../state/simulator_service.dart';
import 'info_tiles.dart';
import 'settings_expand_card.dart';

// The developer groups of the Settings screen, cloned from the kiosk's
// Developer Tools and Simulator Settings, one collapsible card each. The
// whole Settings screen is only reachable by users with an edit permission
// (see the route guard), so these need no check of their own.

Widget _hint(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: TextStyle(
              fontSize: 12, color: Theme.of(context).colorScheme.outline)),
    );

// ── Developer Tools: mode, floating tools, session footer ──────────────────

class DeveloperToolsCard extends StatelessWidget {
  const DeveloperToolsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final sim = context.watch<SimulatorService>();
    final mode = context.watch<BrowsingModeService>().mode;
    return SettingsExpandCard(
      icon: Icons.developer_mode_outlined,
      title: 'Developer Tools',
      children: [
        Row(
          children: [
            const Expanded(child: Text('Mode')),
            DropdownButton<BrowsingMode>(
              value: mode == BrowsingMode.shopping
                  ? BrowsingMode.shopping
                  : BrowsingMode.normal,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(
                    value: BrowsingMode.normal, child: Text('Normal')),
                DropdownMenuItem(
                    value: BrowsingMode.shopping, child: Text('Shopping')),
              ],
              onChanged: (v) {
                if (v != null) browsingModeService.setMode(v);
              },
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Floating dev tools'),
          value: !sim.devToolsHidden,
          onChanged: (v) => v ? sim.showDevTools() : sim.hideDevTools(),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Session info footer'),
          value: sim.showFooter,
          onChanged: sim.saveFooterVisibility,
        ),
      ],
    );
  }
}

// ── Simulators: which shortcut buttons the floating tools show ─────────────

class SimulatorsCard extends StatelessWidget {
  const SimulatorsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final sim = context.watch<SimulatorService>();
    return SettingsExpandCard(
      icon: Icons.touch_app_outlined,
      title: 'Simulators',
      children: [
        _hint(
            context,
            'Which shortcut buttons show in the floating dev tools. Close, '
            '"hide dev tools" and the mode switch are always there.'),
        for (final entry in const {
          SimPinnedButton.home: 'Home',
          SimPinnedButton.settings: 'Settings',
          SimPinnedButton.camera: 'Camera scan',
          SimPinnedButton.productScan: 'Product scan (manual/cached code)',
          SimPinnedButton.browse: 'Browse',
          SimPinnedButton.sessionInfo: 'Session info (toggles the footer)',
        }.entries)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: Text(entry.value),
            value: sim.isPinned(entry.key),
            onChanged: (value) => sim.setPinned(entry.key, value ?? false),
          ),
      ],
    );
  }
}

// ── Scan Options: cached scan codes ────────────────────────────────────────

class ScanOptionsCard extends StatefulWidget {
  const ScanOptionsCard({super.key});

  @override
  State<ScanOptionsCard> createState() => _ScanOptionsCardState();
}

class _ScanOptionsCardState extends State<ScanOptionsCard> {
  late List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    final codes =
        context.read<SimulatorService>().cachedCodes(SimScanType.product);
    _controllers = codes.isEmpty
        ? [TextEditingController()]
        : codes.map((c) => TextEditingController(text: c)).toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addField() {
    setState(() => _controllers.add(TextEditingController()));
  }

  void _removeField(int index) {
    setState(() {
      _controllers[index].dispose();
      _controllers.removeAt(index);
      if (_controllers.isEmpty) _controllers.add(TextEditingController());
    });
  }

  void _save() {
    final codes = _controllers
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    context.read<SimulatorService>().setCachedCodes(SimScanType.product, codes);
    final msg = codes.isEmpty
        ? 'Cleared'
        : 'Saved ${codes.length} code${codes.length == 1 ? '' : 's'}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final sim = context.watch<SimulatorService>();
    final scheme = Theme.of(context).colorScheme;
    return SettingsExpandCard(
      icon: Icons.qr_code_scanner_outlined,
      title: 'Scan Options',
      children: [
        _hint(
            context,
            'The Product scan button fires a random code from this list. '
            'Long-press it to set a one-off code.'),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: const TitleWithInfo(
            'Cache scans',
            'When on, every code the simulator fires (tap, long-press, '
                'camera) is added to this list automatically once it resolves.',
          ),
          subtitle: const Text('Add every fired code to the list',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          value: sim.autoCache,
          onChanged: (value) => sim.setAutoCache(value ?? false),
        ),
        Row(
          children: [
            const Text('Cache size limit'),
            const Spacer(),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: sim.cacheLimit > 1
                  ? () => sim.setCacheLimit(sim.cacheLimit - 1)
                  : null,
            ),
            SizedBox(
              width: 32,
              child: Text(
                '${sim.cacheLimit}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => sim.setCacheLimit(sim.cacheLimit + 1),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _controllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controllers[i],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'UPC ${i + 1}',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.remove_circle_outline, color: scheme.error),
                  onPressed: () => _removeField(i),
                ),
              ],
            ),
          ),
        Row(
          children: [
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add code'),
              onPressed: _addField,
            ),
            const Spacer(),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ],
    );
  }
}

// ── Landing Pages: load and preview a landing page ─────────────────────────

class LandingPagesCard extends StatefulWidget {
  const LandingPagesCard({super.key});

  @override
  State<LandingPagesCard> createState() => _LandingPagesCardState();
}

class _LandingPagesCardState extends State<LandingPagesCard> {
  static const _keys = [
    'CLIENT_LANDING',
    'ADMIN_LANDING',
    'KIOSK_LANDING',
    'SHOPPING_LANDING'
  ];
  late String _selectedKey;
  bool _busy = false;
  String? _statusMsg;

  @override
  void initState() {
    super.initState();
    _selectedKey = switch (browsingModeService.mode) {
      BrowsingMode.kiosk => 'KIOSK_LANDING',
      BrowsingMode.shopping => 'SHOPPING_LANDING',
      BrowsingMode.normal => 'CLIENT_LANDING',
    };
  }

  bool get _supportsWebView =>
      kIsWeb || (!kIsWeb && (Platform.isAndroid || Platform.isIOS));

  void _setStatus(String msg) {
    if (mounted) {
      setState(() {
        _statusMsg = msg;
        _busy = false;
      });
    }
  }

  Future<void> _loadFromRemote() async {
    setState(() {
      _busy = true;
      _statusMsg = null;
    });
    final api = context.read<ApiClient>();
    final token = authService.token;
    final key = _selectedKey;
    try {
      final info = await api.getLandingPage(key, token);
      if (info == null) {
        _setStatus('No landing page found for $key');
        return;
      }
      if (!mounted) return;
      final html = await api.fetchResourceContent(info.resourceUrl, token);
      await LandingCache.writeHtml(key, html, info.contentHash);
      await LocalPrefs.setLandingResourceUrl(key, info.resourceUrl);
      if (!mounted) return;
      setState(() => _busy = false);
      _openWebView(html, source: 'remote');
    } catch (e) {
      _setStatus('Error: $e');
    }
  }

  Future<void> _loadFromLocal() async {
    setState(() {
      _busy = true;
      _statusMsg = null;
    });
    try {
      final html = await LandingCache.readHtml(_selectedKey);
      if (!mounted) return;
      if (html == null) {
        _setStatus('No cached HTML for $_selectedKey');
        return;
      }
      setState(() => _busy = false);
      _openWebView(html, source: 'cache');
    } catch (e) {
      _setStatus('Error: $e');
    }
  }

  void _openWebView(String html, {required String source}) {
    if (!_supportsWebView) {
      setState(() => _statusMsg =
          'WebView not supported on this platform. HTML loaded from $source (${html.length} chars).');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _LandingPreviewScreen(
        html: html,
        title: '$_selectedKey ($source)',
        baseUrl: AppConfig.apiBaseUrl,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SettingsExpandCard(
      icon: Icons.web_outlined,
      title: 'Landing Pages',
      children: [
        _hint(
            context,
            'Load and preview a landing page, either freshly fetched from the '
            'server or from the local cache written by the app.'),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Page key',
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedKey,
              isExpanded: true,
              isDense: true,
              items: _keys
                  .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedKey = v);
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.storage_outlined),
                label: const Text('From local'),
                onPressed: _busy ? null : _loadFromLocal,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text('From remote'),
                onPressed: _busy ? null : _loadFromRemote,
              ),
            ),
          ],
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: LinearProgressIndicator(),
          ),
        if (_statusMsg != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_statusMsg!,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ),
      ],
    );
  }
}

class _LandingPreviewScreen extends StatefulWidget {
  final String html;
  final String title;
  final String baseUrl;
  const _LandingPreviewScreen(
      {required this.html, required this.title, required this.baseUrl});

  @override
  State<_LandingPreviewScreen> createState() => _LandingPreviewScreenState();
}

class _LandingPreviewScreenState extends State<_LandingPreviewScreen> {
  late final WebViewController _controller;

  String get _resolved =>
      LandingCache.resolveAbsolutePaths(widget.html, widget.baseUrl);

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(_resolved, baseUrl: widget.baseUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Reload',
            onPressed: () =>
                _controller.loadHtmlString(_resolved, baseUrl: widget.baseUrl),
          ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
