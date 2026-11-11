import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/address.dart';
import '../services/api_client.dart';
import '../services/api_exceptions.dart';
import '../state/auth_service.dart';
import 'address_form_screen.dart';

/// The customer's saved addresses: list, add, edit, delete, set default.
/// When opened with [pickMode] a tap on an address returns it to the caller
/// (used by checkout).
class AddressesScreen extends StatefulWidget {
  final bool pickMode;
  const AddressesScreen({super.key, this.pickMode = false});

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  List<Address>? _addresses;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = authService.token;
    if (token == null) return;
    setState(() => _error = null);
    try {
      final list = await context.read<ApiClient>().getAddresses(token);
      if (mounted) setState(() => _addresses = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _openForm([Address? a]) async {
    final saved = await Navigator.of(context).push<Address>(
        MaterialPageRoute(builder: (_) => AddressFormScreen(address: a)));
    if (saved != null) await _load();
  }

  Future<void> _makeDefault(Address a) async {
    final token = authService.token;
    if (token == null || a.id == null) return;
    try {
      await context.read<ApiClient>().setDefaultAddress(token, a.id!);
      await _load();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _delete(Address a) async {
    final l10n = AppLocalizations.of(context)!;
    final token = authService.token;
    if (token == null || a.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.addressDeleteConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.addressDelete)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<ApiClient>().deleteAddress(token, a.id!);
      await _load();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final list = _addresses;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.addressesTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: Text(l10n.checkoutAddAddress),
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: TextStyle(color: scheme.error)))
          : list == null
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? Center(
                      child: Text(l10n.addressesEmpty,
                          style: TextStyle(color: scheme.outline)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                      itemCount: list.length,
                      itemBuilder: (ctx, i) {
                        final a = list[i];
                        return Card(
                          elevation: 0,
                          color: scheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: widget.pickMode
                                ? () => Navigator.of(context).pop(a)
                                : () => _openForm(a),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.location_on_outlined,
                                          color: scheme.primary),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          a.label.isNotEmpty
                                              ? a.label
                                              : a.city,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16),
                                        ),
                                      ),
                                      if (a.isDefault)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade600
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(l10n.addressDefaultChip,
                                              style: TextStyle(
                                                  color: Colors.green.shade800,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 12)),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(a.summary),
                                  if (a.recipientName.isNotEmpty ||
                                      a.phone.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        [a.recipientName, a.phone]
                                            .where((e) => e.isNotEmpty)
                                            .join(' · '),
                                        style: TextStyle(color: scheme.outline),
                                      ),
                                    ),
                                  if (!widget.pickMode)
                                    Align(
                                      alignment: AlignmentDirectional.centerEnd,
                                      child: Wrap(
                                        children: [
                                          if (!a.isDefault)
                                            TextButton(
                                                onPressed: () =>
                                                    _makeDefault(a),
                                                child: Text(
                                                    l10n.addressMakeDefault)),
                                          TextButton(
                                              onPressed: () => _openForm(a),
                                              child: Text(l10n.addressEdit)),
                                          TextButton(
                                              onPressed: () => _delete(a),
                                              style: TextButton.styleFrom(
                                                  foregroundColor:
                                                      scheme.error),
                                              child: Text(l10n.addressDelete)),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
