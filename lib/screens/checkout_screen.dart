import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/address.dart';
import '../router/app_router.dart';
import '../services/api_client.dart';
import '../services/api_exceptions.dart';
import '../state/auth_service.dart';
import '../state/order_flow_controller.dart';
import '../state/store_config_service.dart';
import '../utils/money.dart';
import 'address_form_screen.dart';
import 'addresses_screen.dart';

/// Normal-mode (online ordering) checkout: choose pickup or delivery, pick
/// the address, review the totals and place the order. Shopping mode never
/// comes here — its cart creates the order itself.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  List<Address> _addresses = [];
  bool _loading = true;
  bool _placing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    // Online ordering needs an account: anonymous customers sign in first
    // and come back here.
    if (!authService.isLoggedIn) {
      Navigator.of(context).pushReplacementNamed(
        Routes.login,
        arguments: Routes.checkout,
      );
      return;
    }
    final flow = context.read<OrderFlowController>();
    if (flow.cart.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    try {
      _addresses =
          await context.read<ApiClient>().getAddresses(authService.token!);
      // Pickup is the default choice; an address that was picked earlier
      // and has since been removed is dropped.
      flow.shippingMethod ??= 'PICKUP';
      if (flow.addressId != null &&
          !_addresses.any((a) => a.id == flow.addressId)) {
        await flow.setAddress(null);
      }
      if (flow.addressId == null && _addresses.isNotEmpty) {
        final def = _addresses.firstWhere((a) => a.isDefault,
            orElse: () => _addresses.first);
        await flow.setAddress(def.id);
      } else {
        await flow.setAddress(flow.addressId); // fresh quote with options
      }
    } on ApiException catch (e) {
      _error = e.message;
    }
    if (mounted) setState(() => _loading = false);
  }

  Address? _selected(OrderFlowController flow) {
    for (final a in _addresses) {
      if (a.id == flow.addressId) return a;
    }
    return null;
  }

  String _reasonText(AppLocalizations l10n, String? reason) {
    switch (reason) {
      case 'ADDRESS_REQUIRED':
        return l10n.shipAddressRequired;
      default:
        return l10n.shipNotAvailable;
    }
  }

  String _methodTitle(AppLocalizations l10n, String m) =>
      m == 'PICKUP' ? l10n.shipPickup : l10n.shipFree;

  String _methodHint(AppLocalizations l10n, String m) =>
      m == 'PICKUP' ? l10n.shipPickupHint : l10n.shipFreeHint;

  Future<void> _reloadAddresses() async {
    try {
      final list =
          await context.read<ApiClient>().getAddresses(authService.token!);
      if (mounted) setState(() => _addresses = list);
    } on ApiException catch (_) {}
  }

  Future<void> _addAddress() async {
    final saved = await Navigator.of(context).push<Address>(
        MaterialPageRoute(builder: (_) => const AddressFormScreen()));
    if (saved == null || !mounted) return;
    await _reloadAddresses();
    if (mounted) await context.read<OrderFlowController>().setAddress(saved.id);
  }

  Future<void> _pickAddress() async {
    final picked = await Navigator.of(context).push<Address>(MaterialPageRoute(
        builder: (_) => const AddressesScreen(pickMode: true)));
    await _reloadAddresses();
    if (!mounted) return;
    final flow = context.read<OrderFlowController>();
    if (picked != null) {
      await flow.setAddress(picked.id);
    } else if (flow.addressId != null &&
        !_addresses.any((a) => a.id == flow.addressId)) {
      await flow.setAddress(null);
    }
  }

  /// Choosing delivery: use the default address straight away so the option
  /// becomes available; with no address saved, ask for one.
  Future<void> _chooseDelivery(OrderFlowController flow) async {
    flow.setShippingMethod('FREE_SHIPPING');
    if (flow.addressId == null) {
      if (_addresses.isEmpty) {
        await _addAddress();
      } else {
        final def = _addresses.firstWhere((a) => a.isDefault,
            orElse: () => _addresses.first);
        await flow.setAddress(def.id);
      }
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _place() async {
    final l10n = AppLocalizations.of(context)!;
    final flow = context.read<OrderFlowController>();
    final nav = Navigator.of(context);
    setState(() => _placing = true);
    try {
      final order = await flow.checkout();
      if (!mounted) return;
      nav.pushReplacementNamed(Routes.invoice, arguments: order.orderId);
    } on ShippingNotAvailableException {
      _snack(l10n.shipErrNotAvailable);
      await flow.setAddress(flow.addressId); // refresh the options
    } on CouponRejectedException catch (e) {
      await flow.removeCoupon();
      _snack(e.message);
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack(l10n.couponErrGeneric);
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final flow = context.watch<OrderFlowController>();
    final quote = flow.quote;
    final currency = context.watch<StoreConfigService>().storeCurrency;
    final options = quote?.shippingOptions;
    final method = flow.shippingMethod ?? 'PICKUP';
    ShippingOption? current;
    if (options != null) {
      for (final o in options) {
        if (o.method == method) current = o;
      }
    }
    final shippingAmount = current?.amount ?? 0.0;
    final selectedAddress = _selected(flow);
    final delivery = method == 'FREE_SHIPPING';
    final canPlace = !_placing &&
        !flow.busy &&
        quote != null &&
        quote.total > 0 &&
        (options == null || (current?.available ?? false));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.checkoutTitle)),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(l10n.checkoutCreating,
                      style: TextStyle(color: scheme.outline)),
                ],
              ),
            )
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(_error!,
                                style: TextStyle(color: scheme.error)),
                          ),
                        Text(l10n.checkoutDeliveryTitle,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        if (options == null)
                          Text(l10n.shipUnavailableNotice,
                              style: TextStyle(color: scheme.error))
                        else
                          for (final o in options)
                            _MethodCard(
                              title: _methodTitle(l10n, o.method),
                              hint: o.available ||
                                      o.reason == 'ADDRESS_REQUIRED'
                                  ? _methodHint(l10n, o.method)
                                  : _reasonText(l10n, o.reason),
                              note: !o.available &&
                                      o.reason == 'ADDRESS_REQUIRED' &&
                                      method == o.method
                                  ? l10n.shipAddressRequired
                                  : null,
                              amount: o.amount > 0
                                  ? formatMoney(o.amount, currency)
                                  : l10n.shipFreeAmount,
                              selected: method == o.method,
                              // ADDRESS_REQUIRED is solved by this very
                              // screen, so it stays tappable.
                              enabled: o.available ||
                                  o.reason == 'ADDRESS_REQUIRED',
                              onTap: () => o.requiresAddress
                                  ? _chooseDelivery(flow)
                                  : flow.setShippingMethod(o.method),
                            ),
                        if (delivery) ...[
                          const SizedBox(height: 16),
                          Text(l10n.checkoutAddressTitle,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Card(
                            elevation: 0,
                            color: scheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (selectedAddress != null) ...[
                                    Text(
                                      selectedAddress.label.isNotEmpty
                                          ? selectedAddress.label
                                          : selectedAddress.city,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(selectedAddress.summary),
                                    if (selectedAddress.phone.isNotEmpty)
                                      Text(selectedAddress.phone,
                                          style:
                                              TextStyle(color: scheme.outline)),
                                  ] else
                                    Text(l10n.checkoutNoAddress,
                                        style: TextStyle(color: scheme.outline)),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      if (_addresses.isNotEmpty)
                                        OutlinedButton(
                                            onPressed: _pickAddress,
                                            child: Text(
                                                l10n.checkoutChangeAddress)),
                                      OutlinedButton.icon(
                                          onPressed: _addAddress,
                                          icon: const Icon(
                                              Icons.add_location_alt_outlined,
                                              size: 18),
                                          label:
                                              Text(l10n.checkoutAddAddress)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        if (quote != null)
                          _Totals(
                            l10n: l10n,
                            currency: currency,
                            subtotal: quote.subtotal,
                            offersDiscount: quote.discountAmount -
                                (quote.coupon?.discountAmount ?? 0),
                            couponCode: quote.coupon?.code,
                            couponDiscount: quote.coupon?.discountAmount ?? 0,
                            shipping: options == null ? null : shippingAmount,
                            tax: quote.tax,
                            total: quote.total,
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: canPlace ? _place : null,
                        child: _placing
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: Colors.white))
                            : Text(l10n.checkoutPlaceOrder,
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  final String title;
  final String hint;
  final String? note;
  final String amount;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _MethodCard({
    required this.title,
    required this.hint,
    required this.note,
    required this.amount,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 8),
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.5)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: selected ? scheme.primary : Colors.transparent, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected ? scheme.primary : scheme.outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(hint, style: TextStyle(color: scheme.outline)),
                      if (note != null)
                        Text(note!,
                            style: TextStyle(
                                color: scheme.error,
                                fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Text(amount,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  final AppLocalizations l10n;
  final String? currency;
  final double subtotal;
  final double offersDiscount;
  final String? couponCode;
  final double couponDiscount;
  final double? shipping;
  final double tax;
  final double total;

  const _Totals({
    required this.l10n,
    required this.currency,
    required this.subtotal,
    required this.offersDiscount,
    required this.couponCode,
    required this.couponDiscount,
    required this.shipping,
    required this.tax,
    required this.total,
  });

  Widget _row(BuildContext context, String label, String value,
      {bool bold = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: bold ? null : scheme.outline,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                  fontSize: bold ? 18 : null)),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(value,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    fontSize: bold ? 18 : null)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _row(context, l10n.cartSubtotal, formatMoney(subtotal, currency)),
            if (offersDiscount > 0)
              _row(context, l10n.cartDiscount,
                  '-${formatMoney(offersDiscount, currency)}'),
            if (couponCode != null)
              _row(context, '${l10n.couponRowLabel} ($couponCode)',
                  '-${formatMoney(couponDiscount, currency)}'),
            if (shipping != null)
              _row(
                  context,
                  l10n.shipLabel,
                  shipping! > 0
                      ? formatMoney(shipping!, currency)
                      : l10n.shipFreeAmount),
            _row(context, l10n.cartTax, formatMoney(tax, currency)),
            const Divider(),
            _row(context, l10n.cartTotal, formatMoney(total, currency),
                bold: true),
          ],
        ),
      ),
    );
  }
}
