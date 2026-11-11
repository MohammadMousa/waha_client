/// A payment method available to a store in a given mode.
/// provider: REDIRECT (external URL, browser launch), TERMINAL (POS reader),
///           SIMULATED (dev mock). The QR-based kinds belong to the kiosk app.
/// offlineCapable: TERMINAL = true (POS has own connectivity), REDIRECT = false, SIMULATED = true
class PaymentMethod {
  final int id;
  final String key;
  final Map<String, dynamic>? displayName;
  final String provider; // REDIRECT | TERMINAL | SIMULATED
  final bool offlineCapable;
  final int sortOrder;

  const PaymentMethod({
    required this.id,
    required this.key,
    required this.displayName,
    required this.provider,
    required this.offlineCapable,
    required this.sortOrder,
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> json) => PaymentMethod(
        id: json['id'] as int,
        key: json['key'] as String,
        displayName: json['displayName'] as Map<String, dynamic>?,
        provider: json['provider'] as String,
        offlineCapable: json['offlineCapable'] as bool? ?? false,
        sortOrder: json['sortOrder'] as int? ?? 0,
      );
}
