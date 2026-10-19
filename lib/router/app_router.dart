import 'package:flutter/material.dart';

import '../models/product.dart';
import '../screens/browse_screen.dart';
import '../screens/cart_screen.dart';
import '../screens/categories_screen.dart';
import '../screens/checkout_screen.dart';
import '../screens/invoice_screen.dart';
import '../screens/landing_screen.dart';
import '../screens/login_screen.dart';
import '../screens/orders_screen.dart';
import '../screens/pay_screen.dart';
import '../screens/product_detail_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/register_screen.dart';
import '../screens/scan_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/store_picker_screen.dart';
import '../screens/success_screen.dart';
import '../state/browsing_mode_service.dart';
import '../widgets/hardware_scan_listener.dart';

/// Lets code outside the routed page tree push/pop navigation and know
/// which route is on top, without needing a per-route BuildContext of its
/// own. Passing this key's own currentContext to Navigator.of()/
/// showDialog()/showModalBottomSheet() works because Navigator.of()
/// special-cases a context that IS a NavigatorState's own element.
final navigatorKey = GlobalKey<NavigatorState>();

/// Tracks the currently-top route's name for code that isn't built inside
/// any specific route. Register once via MaterialApp's navigatorObservers
/// — see main.dart.
class KioskRouteObserver extends NavigatorObserver {
  static final ValueNotifier<String?> currentRouteName = ValueNotifier(null);

  void _update(Route<dynamic>? route) {
    final name = route?.settings.name;
    // A small notice dialog on top of a page does not change which page the
    // customer is on, so anything watching this must keep running
    // underneath it — otherwise a "Not found" dialog left on screen would
    // stop it for good.
    if (name != null && Routes.transientOverlays.contains(name)) return;
    currentRouteName.value = name;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _update(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _update(previousRoute);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _update(previousRoute);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _update(newRoute);
}

/// Returns to Landing without rebuilding it.
///
/// Landing is the root route and can host a WebView (a server-configured
/// landing page). Replacing it with pushNamedAndRemoveUntil(landing, (_) =>
/// false) destroys the live WebView and builds a new one, which shows a
/// blank screen until the page paints again — and creating/destroying
/// WebViews repeatedly is costly. Popping down to the root keeps the
/// already-painted Landing alive instead. Falls back to the rebuild only
/// if the root is somehow not Landing (e.g. a login flow that replaced it).
void goHomeKeepingLanding(NavigatorState nav) {
  String? rootName;
  nav.popUntil((route) {
    if (route.isFirst) rootName = route.settings.name;
    return route.isFirst;
  });
  if (rootName != Routes.landing) {
    nav.pushNamedAndRemoveUntil(Routes.landing, (route) => false);
  }
}

class Routes {
  /// Name given to the one-at-a-time scan error / blocked-scan dialog (see
  /// utils/scan_actions.dart). It is listed in [transientOverlays].
  static const scanError = '/scan-error';

  /// Routes that are only notices on top of a page: KioskRouteObserver
  /// ignores them, so the page underneath stays "the current route".
  static const transientOverlays = <String>{scanError};

  static const landing = '/';
  static const scan = '/scan';
  static const cart = '/cart';
  static const checkout = '/checkout';
  static const pay = '/pay';
  static const success = '/success';
  static const settings = '/settings';
  static const profile = '/profile';
  static const browse = '/browse';
  static const productDetail = '/browse/product';
  static const register = '/register';
  static const login = '/login';
  static const storePicker = '/store-picker';
  static const invoice = '/invoice';
  static const orders = '/orders';
  static const search = '/search';
  static const categories = '/categories';

  /// Screens reachable while navigation is restricted (Shopping mode only
  /// here — waha_client has no Kiosk mode): "customer already has the
  /// item in hand" is what's restricted. Settings, Profile, Register,
  /// Login, and Store Picker are deliberately excluded — restricted
  /// navigation shouldn't offer a way to reach account/config screens
  /// mid-session.
  // browse/categories/search/productDetail are intentionally included so
  // that HTML landing-page banners (href="/screen?name=browse_screen&tag=X")
  // can navigate to catalog screens from Shopping mode without being
  // blocked by the nav guard.
  static const kioskAllowlist = {landing, scan, cart, checkout, invoice, pay, success,
      browse, categories, search, productDetail, settings};

  /// Reused (see onGenerateRoute) to decide where the ambient hardware-
  /// scanner listener mounts: the same product/cart screens are exactly
  /// where a barcode/keyboard-wedge scan should always be accepted, in
  /// every mode — not just Shopping's restricted set. Deliberately NOT the
  /// same set as kioskAllowlist above — settings has no business accepting
  /// a scan into the cart in the background.
  static const scanEnabledRoutes = {landing, scan, cart, checkout, invoice, pay, success,
      browse, categories, search, productDetail};
}

/// Route guard.
///
/// Navigation lock applies to Shopping mode: any route outside
/// [Routes.kioskAllowlist] bounces back to Landing. Normal mode gets full
/// navigation.
///
/// Reads `browsingModeService.mode` directly rather than through Provider —
/// this function gets no BuildContext, so it can't watch a
/// ChangeNotifier; it just reads the current value fresh on every
/// navigation, which is what's needed here.
Route<dynamic> onGenerateRoute(RouteSettings settings) {
  final name = settings.name ?? Routes.landing;
  final mode = browsingModeService.mode;
  final isRestrictedNav = mode == BrowsingMode.shopping;

  Widget page;
  if (isRestrictedNav && !Routes.kioskAllowlist.contains(name)) {
    page = const LandingScreen();
  } else {
    switch (name) {
      case Routes.landing:
        page = const LandingScreen();
        break;
      case Routes.scan:
        page = const ScanScreen();
        break;
      case Routes.cart:
        page = const CartScreen();
        break;
      case Routes.checkout:
        page = const CheckoutScreen();
        break;
      case Routes.invoice:
        final orderId = settings.arguments as String?;
        page = orderId != null
            ? InvoiceScreen(orderId: orderId)
            : const LandingScreen();
        break;
      case Routes.pay:
        page = const PayScreen();
        break;
      case Routes.success:
        page = const SuccessScreen();
        break;
      case Routes.settings:
        page = const SettingsScreen();
        break;
      case Routes.profile:
        page = const ProfileScreen();
        break;
      case Routes.browse:
        final browseArgs = settings.arguments;
        final categoryId = browseArgs is Map ? browseArgs['categoryId'] as int? : null;
        final browseTitle = browseArgs is Map ? browseArgs['title'] as String? : null;
        final searchQuery = browseArgs is Map ? browseArgs['searchQuery'] as String? : null;
        page = BrowseScreen(categoryId: categoryId, browseTitle: browseTitle, searchQuery: searchQuery);
        break;
      case Routes.register:
        page = const RegisterScreen();
        break;
      case Routes.login:
        page = const LoginScreen();
        break;
      case Routes.storePicker:
        page = const StorePickerScreen();
        break;
      case Routes.orders:
        page = const OrdersScreen();
        break;
      case Routes.search:
        page = const SearchScreen();
        break;
      case Routes.categories:
        page = const CategoriesScreen();
        break;
      case Routes.productDetail:
        final product = settings.arguments;
        page = product is Product
            ? ProductDetailScreen(product: product)
            : const LandingScreen(); // no product passed — bad nav, bail safely
        break;
      default:
        page = const LandingScreen();
    }
  }

  return MaterialPageRoute(
    settings: settings,
    builder: (_) => Stack(
      children: [
        page,
        // Ambient hardware-scanner capture (a USB/BT keyboard-wedge
        // scanner, or Normal mode's own camera scan) — mounted directly on
        // whichever product/cart screen is on top, not dependent on any
        // TextField holding focus, so it survives navigation away from
        // Landing.
        if (Routes.scanEnabledRoutes.contains(name)) const HardwareScanListener(),
      ],
    ),
  );
}
