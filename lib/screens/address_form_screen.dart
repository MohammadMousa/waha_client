import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/address.dart';
import '../services/api_client.dart';
import '../services/api_exceptions.dart';
import '../state/auth_service.dart';

/// Add or edit a saved address. Pops with the saved [Address] on success.
/// Only city, street and phone are required; the rest follow the Saudi
/// national-address fields and stay optional.
class AddressFormScreen extends StatefulWidget {
  final Address? address;
  const AddressFormScreen({super.key, this.address});

  @override
  State<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends State<AddressFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label;
  late final TextEditingController _recipient;
  late final TextEditingController _phone;
  late final TextEditingController _building;
  late final TextEditingController _street;
  late final TextEditingController _secondary;
  late final TextEditingController _district;
  late final TextEditingController _city;
  late final TextEditingController _postal;
  late final TextEditingController _notes;
  bool _isDefault = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final a = widget.address;
    _label = TextEditingController(text: a?.label);
    _recipient = TextEditingController(text: a?.recipientName);
    _phone = TextEditingController(text: a?.phone);
    _building = TextEditingController(text: a?.buildingNumber);
    _street = TextEditingController(text: a?.streetName);
    _secondary = TextEditingController(text: a?.secondaryNumber);
    _district = TextEditingController(text: a?.district);
    _city = TextEditingController(text: a?.city);
    _postal = TextEditingController(text: a?.postalCode);
    _notes = TextEditingController(text: a?.additionalInfo);
    _isDefault = a?.isDefault ?? false;
  }

  @override
  void dispose() {
    for (final c in [
      _label, _recipient, _phone, _building, _street, _secondary,
      _district, _city, _postal, _notes
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context)!;
    final token = authService.token;
    if (token == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    final nav = Navigator.of(context);
    try {
      final saved = await api.saveAddress(
        token,
        Address(
          id: widget.address?.id,
          label: _label.text,
          recipientName: _recipient.text,
          phone: _phone.text,
          buildingNumber: _building.text,
          streetName: _street.text,
          secondaryNumber: _secondary.text,
          district: _district.text,
          city: _city.text,
          postalCode: _postal.text,
          countryCode: widget.address?.countryCode ?? '',
          additionalInfo: _notes.text,
          isDefault: _isDefault,
        ),
      );
      if (mounted) nav.pop(saved);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error =
            e.statusCode == 409 ? l10n.addressLimitReached : e.message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController c, String label,
      {bool required = false,
      TextInputType? keyboard,
      int maxLength = 255,
      String? Function(String?)? validator,
      int lines = 1}) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: keyboard,
        maxLength: maxLength,
        maxLines: lines,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          border: const OutlineInputBorder(),
          counterText: '',
        ),
        validator: (v) {
          final t = (v ?? '').trim();
          if (required && t.isEmpty) return l10n.addressRequiredField;
          return validator?.call(t);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final editing = widget.address != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? l10n.addressEditTitle : l10n.addressNew),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              _field(_label, l10n.addressFieldLabel, maxLength: 60),
              _field(_recipient, l10n.addressFieldRecipient),
              _field(_phone, l10n.addressFieldPhone,
                  required: true,
                  keyboard: TextInputType.phone,
                  maxLength: 30, validator: (t) {
                final ok = RegExp(r'^[0-9+\s()\-]{6,30}$').hasMatch(t ?? '');
                return ok ? null : l10n.addressInvalidPhone;
              }),
              _field(_city, l10n.addressFieldCity, required: true),
              _field(_district, l10n.addressFieldDistrict),
              _field(_street, l10n.addressFieldStreet, required: true),
              Row(
                children: [
                  Expanded(
                    child: _field(_building, l10n.addressFieldBuilding,
                        keyboard: TextInputType.number, maxLength: 10),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(_secondary, l10n.addressFieldSecondary,
                        keyboard: TextInputType.number, maxLength: 10),
                  ),
                ],
              ),
              _field(_postal, l10n.addressFieldPostal,
                  keyboard: TextInputType.number, maxLength: 10),
              _field(_notes, l10n.addressFieldNotes, lines: 2),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.addressFieldDefault),
                value: _isDefault,
                onChanged: (v) => setState(() => _isDefault = v),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5))
                      : Text(l10n.addressSave),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
