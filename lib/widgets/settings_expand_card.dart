import 'package:flutter/material.dart';

/// A collapsible Settings group in the same style as the Server Connection
/// panel: flat tinted card, tappable header (icon, bold title, chevron),
/// divider, then the content. Collapsed by default.
class SettingsExpandCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const SettingsExpandCard({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  State<SettingsExpandCard> createState() => _SettingsExpandCardState();
}

class _SettingsExpandCardState extends State<SettingsExpandCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                  Icon(widget.icon, color: scheme.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(widget.title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.children,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
