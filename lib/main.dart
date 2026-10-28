import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'l10n/generated/app_localizations.dart';
import 'router/app_router.dart';
import 'services/api_client.dart';
import 'services/app_messenger.dart';
import 'services/app_info.dart';
import 'services/local_prefs.dart';
import 'services/trace_log.dart';
import 'state/auth_service.dart';
import 'state/browsing_mode_service.dart';
import 'state/locale_service.dart';
import 'state/order_flow_controller.dart';
import 'state/permission_service.dart';
import 'state/simulator_service.dart';
import 'state/startup_connection.dart';
import 'widgets/connection_gate_overlay.dart';
import 'state/store_config_service.dart';

void main() {
  // Diagnostic-only: catches any uncaught Dart error anywhere in the app
  // (including ones Flutter's own FlutterError.onError below doesn't reach,
  // e.g. inside a Future not awaited by the framework) and logs it to the
  // console via TraceLog — see that file's doc comment for why there is no
  // native log on this (web/Android/Linux customer) app.
  runZonedGuarded(() async {
    // Needed before touching any platform channel (SharedPreferences included)
    // pre-runApp.
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      TraceLog.log(
        'FlutterError: ${details.exceptionAsString()}\n${details.stack}',
      );
    };

    // Initialize audioplayers audio context on non-web platforms so sounds
    // are routed correctly and not silently discarded by the Android audio system.
    if (!kIsWeb) {
      await AudioPlayer.global.setAudioContext(AudioContext());
    }
    await LocalPrefs.init();
    await AppInfo.init();
    await AppConfig.initConnection();
    await AppConfig.loadRuntimeConfig();
    const loggingDefine = bool.fromEnvironment('LOGGING');
    if (loggingDefine && !LocalPrefs.loggingEnabled) {
      await LocalPrefs.setLoggingEnabled(true);
    }
    unawaited(TraceLog.applyEffective());
    // One shared instance for the app's whole lifetime — not a fresh
    // ApiClient() per use. A separate instance would mean a separate
    // underlying http.Client with its own unwarmed connection pool, so the
    // network warm-up below (and whatever resolveStartupAuth's own calls
    // do) wouldn't carry over to the client screens actually use for
    // checkout/payment. See ApiClient._send's retry comment for the
    // symptom this and the warm-up together are meant to fix.
    final apiClient = ApiClient();
    unawaited(
      apiClient.getConfig().catchError((_) => <String, String>{}),
    ); // fire-and-forget warm-up — pays the DNS/TCP/TLS cost now, not at checkout
    await _resolveStartupConfig(apiClient);
    runApp(WahaApp(apiClient: apiClient));
  }, (error, stack) {
    TraceLog.log('Uncaught zone error: $error\n$stack');
  });
}

/// Applies every persisted/overridden config value once at startup, all
/// with `persist: false` — these are LOADS, not new user choices, so
/// re-writing what was just read back would be redundant at best. The
/// one exception is the dart-define mode fallback: that one DOES persist
/// once applied (see below), so it becomes durable from that point on
/// rather than needing to be re-supplied via --dart-define on every launch.
Future<void> _resolveStartupConfig(ApiClient apiClient) async {
  // Mode: URL override (web, ephemeral, never persisted — the real-world
  // entry into Shopping mode is a `?mode=shopping` link, typically from a
  // kiosk's own QR code) > persisted value (survives restart) > dart-define
  // (first-run seed, becomes persisted from here on) > Normal (the
  // constructed default for this app).
  final urlMode = AppConfig.urlOverrideMode;
  if (urlMode != null) {
    browsingModeService.setMode(urlMode, persist: false);
  } else {
    final persistedMode = parseBrowsingMode(LocalPrefs.mode);
    if (persistedMode != null) {
      browsingModeService.setMode(persistedMode, persist: false);
    } else {
      final defineMode = AppConfig.dartDefineMode;
      if (defineMode != null) {
        browsingModeService.setMode(defineMode); // persists — becomes durable
      }
      // else: stays at whichever mode it was constructed with (Normal).
    }
  }

  final persistedStoreId = LocalPrefs.storeId;
  if (persistedStoreId != null) {
    storeConfigService.setStoreId(persistedStoreId, persist: false);
  }

  final persistedLocale = LocalPrefs.locale;
  if (persistedLocale != null) {
    localeService.setLocale(Locale(persistedLocale), persist: false);
  }

  final beforeWarn = LocalPrefs.beforeWarnSeconds;
  final beforeCountdown = LocalPrefs.beforeCountdownSeconds;
  final afterWarn = LocalPrefs.afterWarnSeconds;
  final afterCountdown = LocalPrefs.afterCountdownSeconds;
  if (beforeWarn != null ||
      beforeCountdown != null ||
      afterWarn != null ||
      afterCountdown != null) {
    kioskTimerConfig.update(
      beforeInvoiceIdleWarningAfter:
          beforeWarn != null ? Duration(seconds: beforeWarn) : null,
      beforeInvoiceWarningCountdown:
          beforeCountdown != null ? Duration(seconds: beforeCountdown) : null,
      afterInvoiceIdleWarningAfter:
          afterWarn != null ? Duration(seconds: afterWarn) : null,
      afterInvoiceWarningCountdown:
          afterCountdown != null ? Duration(seconds: afterCountdown) : null,
      persist: false,
    );
  }

  // Auth resolution — reuses the shared apiClient passed in (see main()'s
  // comment on why that matters for connection warming) rather than a
  // throwaway instance. Try cached token, fall back to cached credentials,
  // fall back to a fresh throwaway account for Shopping only. See
  // AuthService.resolveStartupAuth for the full precedence and the
  // failure/timeout handling. Awaited (not fire-and-forget) so the very
  // first frame already reflects whether there's a session, rather than
  // flashing a logged-out state for a moment first. Mode must already be
  // resolved by this point — Shopping's auto-account behavior depends on it.
  // If the server can't be reached at all, don't sit through the slow
  // timeouts of every call below — show the "Connecting…" popup instead,
  // which retries on a growing schedule and finishes this sign-in once the
  // server answers (see StartupConnection).
  final reachError = await apiClient.probe();
  if (reachError != null) {
    startupConnection.begin(apiClient, reachError);
  } else {
    await authService.resolveStartupAuth(apiClient, browsingModeService.mode);
  }
}

class WahaApp extends StatelessWidget {
  final ApiClient apiClient;
  const WahaApp({required this.apiClient, super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // .value, not create: (_) => ApiClient() — reuses the same
        // instance main() already warmed a connection on, instead of a
        // fresh one with its own cold connection pool.
        Provider.value(value: apiClient),
        ChangeNotifierProvider(
          create: (context) => OrderFlowController(context.read<ApiClient>()),
        ),
        ChangeNotifierProvider.value(value: storeConfigService),
        ChangeNotifierProvider.value(value: browsingModeService),
        ChangeNotifierProvider.value(value: localeService),
        ChangeNotifierProvider.value(value: authService),
        ChangeNotifierProvider.value(value: permissionService),
        ChangeNotifierProvider(create: (_) => SimulatorService()),
      ],
      // Builder, not MaterialApp directly — MaterialApp needs a context
      // BELOW MultiProvider's providers to `watch` LocaleService for the
      // `locale:` param; WahaApp.build's own context is above them.
      child: Builder(
        builder: (context) {
          final locale = context.watch<LocaleService>().locale;
          return MaterialApp(
            title: 'Waha',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorSchemeSeed: const Color(0xFF6B1A2A),
              useMaterial3: true,
            ),
            locale: locale,
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            scaffoldMessengerKey: rootScaffoldMessengerKey,
            navigatorKey: navigatorKey,
            navigatorObservers: [KioskRouteObserver()],
            onGenerateRoute: onGenerateRoute,
            // Covers every route while the server is unreachable at
            // startup; needs no Overlay so it can sit above the Navigator.
            builder: (context, child) =>
                ConnectionGateOverlay(child: child ?? const SizedBox.shrink()),
            initialRoute: Routes.landing,
          );
        },
      ),
    );
  }
}
