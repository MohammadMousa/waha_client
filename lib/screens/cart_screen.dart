import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/quote.dart';
import '../router/app_router.dart';
import 'camera_scan_screen.dart';
import '../services/api_exceptions.dart';
import '../services/local_prefs.dart';
import '../state/browsing_mode_service.dart';
import '../state/locale_service.dart';
import '../state/order_flow_controller.dart';
import '../state/permission_service.dart';
import '../state/simulator_service.dart';
import '../state/store_config_service.dart';
import '../utils/money.dart';
import '../utils/scan_actions.dart';
import '../widgets/cart_line_tile.dart';
import '../widgets/waha_bottom_nav.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  // Secret gesture: 10 taps anywhere on the cart body within 3 s. Does
  // nothing unless the user holds an edit permission — then it reveals the
  // dev tools and opens Settings (no PIN).
  int _tapCount = 0;
  Timer? _tapTimer;

  void _onBodyTap() {
    if (!permissionService.canOpenDevTools) return;
    _tapTimer?.cancel();
    _tapCount++;
    if (_tapCount >= 10) {
      _tapCount = 0;
      context.read<SimulatorService>().showDevTools();
      Navigator.of(context).pushNamed(Routes.settings);
    } else {
      _tapTimer = Timer(const Duration(seconds: 3), () => _tapCount = 0);
    }
  }

  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  final Set<int> _flashingIds = {};
  Timer? _flashTimer;
  late final OrderFlowController _flow;

  @override
  void initState() {
    super.initState();
    _flow = context.read<OrderFlowController>();
    _flow.addListener(_onFlowChanged);
  }

  void _onFlowChanged() {
    final flow = _flow;
    final touched = flow.lastTouchedProductId;
    if (touched == null || !mounted) return;
    flow.lastTouchedProductId = null; // consume — no notifyListeners needed

    // Flash highlight
    setState(() => _flashingIds.add(touched));
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _flashingIds.clear());
    });

    // Scroll the item into view after the frame renders with the new item
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[touched];
      final ctx = key?.currentContext;
      if (ctx != null && mounted) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            alignment: 0.5);
      }
    });
  }

  GlobalKey _keyFor(int productId) =>
      _itemKeys.putIfAbsent(productId, GlobalKey.new);

  @override
  void dispose() {
    _flow.removeListener(_onFlowChanged);
    _scrollController.dispose();
    _flashTimer?.cancel();
    _tapTimer?.cancel();
    super.dispose();
  }

  bool _creatingOrder = false;

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String _couponMessage(String code) {
    final l = AppLocalizations.of(context)!;
    switch (code) {
      case 'COUPON_NOT_FOUND':
        return l.couponErrNotFound;
      case 'COUPON_DISABLED':
        return l.couponErrDisabled;
      case 'COUPON_NOT_YET_VALID':
        return l.couponErrNotYetValid;
      case 'COUPON_EXPIRED':
        return l.couponErrExpired;
      case 'COUPON_WRONG_STORE':
        return l.couponErrWrongStore;
      case 'COUPON_USAGE_LIMIT_REACHED':
        return l.couponErrUsageLimit;
      case 'COUPON_USER_LIMIT_REACHED':
        return l.couponErrUserLimit;
      case 'COUPON_AMOUNT_EXHAUSTED':
      case 'COUPON_USER_AMOUNT_EXHAUSTED':
        return l.couponErrAmountExhausted;
      case 'COUPON_MINIMUM_ORDER_NOT_MET':
        return l.couponErrMinimumOrder;
      case 'COUPON_NOT_COMBINABLE':
        return l.couponErrNotCombinable;
      case 'COUPON_NOT_APPLICABLE':
        return l.couponErrNotApplicable;
      case 'ORDER_TOTAL_NOT_POSITIVE':
        return l.couponErrTotalNotPositive;
      default:
        return l.couponErrGeneric;
    }
  }

  Future<void> _openCouponSheet() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final fieldFocus = FocusNode();
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 4, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.couponSheetTitle,
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            // No autofocus: the keypad opens only when the customer taps the
            // field. The camera button hands focus away before opening the
            // scanner and the scanned code is applied straight away, so a
            // scan never types into the field or brings the keypad up.
            TextField(
              controller: controller,
              focusNode: fieldFocus,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: l10n.couponCodeHint,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: l10n.couponScanTooltip,
                  icon: const Icon(Icons.photo_camera_outlined),
                  onPressed: () async {
                    fieldFocus.unfocus();
                    final scanned = await Navigator.of(ctx).push<String>(
                      MaterialPageRoute(
                        builder: (_) => CameraScanScreen(
                          title: l10n.couponScanTitle,
                          showClearAll: false,
                        ),
                      ),
                    );
                    fieldFocus.unfocus();
                    if (scanned != null &&
                        scanned.trim().isNotEmpty &&
                        ctx.mounted) {
                      Navigator.of(ctx).pop(_couponFromScan(scanned));
                    }
                  },
                ),
              ),
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: Text(l10n.couponApply),
            ),
          ],
        ),
      ),
    );
    // Not disposed here: the sheet is still animating out and uses them.
    if (code == null || code.trim().isEmpty || !mounted) return;
    final rejected = await context.read<OrderFlowController>().applyCoupon(code);
    if (!mounted) return;
    _snack(rejected == null ? l10n.couponAppliedMessage : _couponMessage(rejected));
  }

  /// Shopping mode: the customer is already in the store, so the order is
  /// created right here in the cart — no checkout screen, no address, no
  /// shipping — and the flow goes straight to payment.
  Future<void> _payInCart() async {
    if (_creatingOrder) return;
    setState(() => _creatingOrder = true);
    final flow = context.read<OrderFlowController>();
    final nav = Navigator.of(context);
    try {
      final order = await flow.checkout();
      if (!mounted) return;
      nav.pushNamed(Routes.invoice, arguments: order.orderId);
    } on CouponRejectedException catch (e) {
      await flow.removeCoupon();
      _snack(_couponMessage(e.code));
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack(AppLocalizations.of(context)!.couponErrGeneric);
    } finally {
      if (mounted) setState(() => _creatingOrder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<OrderFlowController>();
    final mode = context.watch<BrowsingModeService>().mode;
    final isShopping = mode == BrowsingMode.shopping;
    final isKiosk = mode == BrowsingMode.kiosk;
    final quote = flow.quote;
    final l10n = AppLocalizations.of(context)!;
    final currency = context.watch<StoreConfigService>().storeCurrency
        ?? flow.order?.currency;

    // Hidden by default in Kiosk mode — the polished design has nothing
    // below the summary card and action buttons. Settings can opt back in.
    final showBottomNav = !isKiosk || LocalPrefs.showCartMenuInKiosk;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.cartTitle),
        actions: [
          // The Cancel button on the summary card now covers "empty the
          // cart" — a second, separate clear-cart action here was
          // redundant. A language toggle is more useful in this slot.
          IconButton(
            icon: const Icon(Icons.language_outlined),
            tooltip: l10n.settingsLanguage,
            onPressed: () {
              final next = localeService.locale.languageCode == 'en'
                  ? const Locale('ar')
                  : const Locale('en');
              localeService.setLocale(next);
            },
          ),
        ],
      ),
      bottomNavigationBar:
          showBottomNav ? const WahaBottomNav(current: BottomNavTab.cart) : null,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _onBodyTap,
        child: Column(
        children: [
          if (flow.lastError != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade50,
              padding: const EdgeInsets.all(12),
              child: Text(flow.lastError!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: flow.cart.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shopping_cart_outlined,
                              size: 72, color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 16),
                          Text(
                            l10n.cartEmptyTitle,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l10n.cartEmptySubtitle,
                            style: TextStyle(color: Theme.of(context).colorScheme.outline),
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            icon: Icon(isShopping
                                ? Icons.qr_code_scanner
                                : Icons.home_outlined),
                            label: Text(
                              isShopping ? l10n.ctaStartScanning : l10n.ctaContinueShopping,
                            ),
                            onPressed: () {
                              if (isShopping) {
                                openCameraAndAddToCart(context);
                              } else {
                                goHomeKeepingLanding(Navigator.of(context));
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: flow.cart.length,
                    itemBuilder: (context, i) {
                      final item = flow.cart[i];
                      QuoteLine? line;
                      if (quote != null) {
                        for (final l in quote.items) {
                          if (l.productId == item.productId) { line = l; break; }
                        }
                      }
                      final controller = context.read<OrderFlowController>();
                      final flashing = _flashingIds.contains(item.productId);
                      return AnimatedContainer(
                        key: _keyFor(item.productId),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOut,
                        decoration: BoxDecoration(
                          color: flashing
                              ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.55)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: CartLineTile(
                          item: item,
                          line: line,
                          currency: currency,
                          onQuantityChanged: (q) =>
                              controller.updateQuantity(item.productId, q),
                          onRemove: () => controller.removeItem(item.productId),
                        ),
                      );
                    },
                  ),
          ),
          _CartSummaryCard(
            subtotal: quote?.subtotal ?? 0.0,
            tax: quote?.tax ?? 0.0,
            total: quote?.total ?? 0.0,
            discount: quote?.discountAmount ?? 0.0,
            coupon: quote?.coupon,
            currency: currency,
            l10n: l10n,
            // A cart the offers bring down to nothing due is not an order.
            zeroDue: quote != null && flow.cart.isNotEmpty && quote.total <= 0,
            canCheckout: flow.cart.isNotEmpty &&
                !flow.busy &&
                !_creatingOrder &&
                !(quote != null && quote.total <= 0),
            // Coupons are entered right here in the cart, in every mode. Both
            // round buttons stay on screen with an empty cart (dimmed) so the
            // panel never changes shape.
            onCoupon: flow.cart.isNotEmpty ? _openCouponSheet : null,
            onRemoveCoupon: () => context.read<OrderFlowController>().removeCoupon(),
            onClear: flow.cart.isEmpty
                ? null
                : () {
                    context.read<OrderFlowController>().clearCart();
                    goHomeKeepingLanding(Navigator.of(context));
                  },
            // Shopping: "Buy & Pay" creates the order here. Normal mode
            // (online ordering) opens the checkout screen.
            checkoutLabel:
                isShopping ? l10n.checkoutButton : l10n.cartCheckoutButton,
            onCheckout: isShopping
                ? _payInCart
                : () => Navigator.of(context).pushNamed(Routes.checkout),
          ),
        ],
        ),
      ),
    );
  }
}

// ── Summary card — collapsed shows only the grand total; subtotal/tax only
// show once expanded. Always rendered (even on an empty cart, as 0.00) so
// the layout never jumps between empty and non-empty states. ──────────────

class _CartSummaryCard extends StatefulWidget {
  final double subtotal;
  final double discount;
  final AppliedCoupon? coupon;
  final double tax;
  final double total;
  final String? currency;
  final AppLocalizations l10n;
  final bool canCheckout;
  final bool zeroDue;
  final VoidCallback? onCoupon;
  final VoidCallback onRemoveCoupon;
  final VoidCallback? onClear;
  final VoidCallback onCheckout;
  final String checkoutLabel;

  const _CartSummaryCard({
    required this.subtotal,
    required this.discount,
    required this.coupon,
    required this.tax,
    required this.total,
    required this.currency,
    required this.l10n,
    required this.canCheckout,
    required this.zeroDue,
    required this.onCoupon,
    required this.onRemoveCoupon,
    required this.onClear,
    required this.onCheckout,
    required this.checkoutLabel,
  });

  @override
  State<_CartSummaryCard> createState() => _CartSummaryCardState();
}

class _CartSummaryCardState extends State<_CartSummaryCard> {
  bool _expanded = false;

  // Wide/landscape screens: the card stops growing past this and centers
  // instead, so the header and buttons don't stretch edge-to-edge forever.
  static const _maxWidth = 480.0;

  Widget _circleButton({
    required Color color,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: onPressed == null ? color.withValues(alpha: 0.4) : color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(icon, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = widget.l10n;
    final coupon = widget.coupon;
    // The coupon's share is already inside the total discount; show the
    // offers' part and the coupon's part as separate rows.
    final offersDiscount =
        coupon == null ? widget.discount : widget.discount - coupon.discountAmount;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Card(
            elevation: 0,
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Text(
                          l10n.cartTotal,
                          style: TextStyle(color: scheme.outline, fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Text(
                          _fmt(widget.total, widget.currency),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                          color: scheme.outline,
                        ),
                      ],
                    ),
                  ),
                ),
                if (coupon != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                    child: Row(
                      children: [
                        Icon(Icons.local_offer_outlined,
                            size: 20, color: Colors.green.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${l10n.couponRowLabel} ${coupon.code}',
                            style: TextStyle(
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            '-${_fmt(coupon.discountAmount, widget.currency)}',
                            style: TextStyle(
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: l10n.couponRemove,
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: widget.onRemoveCoupon,
                        ),
                      ],
                    ),
                  ),
                if (_expanded) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Column(
                      children: [
                        if (offersDiscount > 0) ...[
                          _SummaryRow(
                            l10n.cartDiscount,
                            -offersDiscount,
                            currency: widget.currency,
                          ),
                          const SizedBox(height: 4),
                        ],
                        if (coupon != null) ...[
                          _SummaryRow(
                            '${l10n.couponRowLabel} (${coupon.code})',
                            -coupon.discountAmount,
                            currency: widget.currency,
                          ),
                          const SizedBox(height: 4),
                        ],
                        _SummaryRow(l10n.cartSubtotal, widget.subtotal, currency: widget.currency),
                        const SizedBox(height: 4),
                        _SummaryRow(l10n.cartTax, widget.tax, currency: widget.currency),
                      ],
                    ),
                  ),
                ],
                if (widget.zeroDue)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Text(
                      l10n.cartZeroDueHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: scheme.error, fontWeight: FontWeight.w600),
                    ),
                  ),
                // Action row: round coupon button, wide pay button, round
                // clear button. The row follows the language direction, so
                // in Arabic the coupon button sits on the right and clear on
                // the left, and in English they swap.
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Row(
                    children: [
                      _circleButton(
                        color: Theme.of(context).colorScheme.primary,
                        icon: Icons.local_offer_outlined,
                        tooltip: l10n.couponButtonTooltip,
                        onPressed: widget.onCoupon,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              disabledBackgroundColor:
                                  Colors.green.shade700.withValues(alpha: 0.4),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: widget.canCheckout ? widget.onCheckout : null,
                            child: Text(
                              widget.checkoutLabel,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _circleButton(
                        color: Colors.red.shade700,
                        icon: Icons.remove_shopping_cart_outlined,
                        tooltip: l10n.clearCartTooltip,
                        onPressed: widget.onClear,
                      ),
                    ],
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

class _SummaryRow extends StatelessWidget {
  final String label;
  final double value;
  final String? currency;
  const _SummaryRow(this.label, this.value, {this.currency});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
        Text(_fmt(value, currency), style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

String _fmt(double amount, String? currency) => formatMoney(amount, currency);


/// A coupon QR normally carries `coupon=CODE`; anything else scanned from the
/// coupon scanner is taken whole as the code.
String _couponFromScan(String raw) {
  final t = raw.trim();
  final m = RegExp(r'(?:^|[?&;\s])coupon=([^&;\s]+)', caseSensitive: false)
      .firstMatch(t);
  if (m != null) {
    final v = Uri.decodeComponent(m.group(1)!).trim();
    if (v.isNotEmpty) return v;
  }
  return t;
}
