/// A saved delivery address of a signed-in customer (GET /api/addresses).
class Address {
  final int? id;
  final String label;
  final String recipientName;
  final String phone;
  final String buildingNumber;
  final String streetName;
  final String secondaryNumber;
  final String district;
  final String city;
  final String postalCode;
  final String countryCode;
  final String additionalInfo;
  final bool isDefault;

  const Address({
    this.id,
    this.label = '',
    this.recipientName = '',
    required this.phone,
    this.buildingNumber = '',
    required this.streetName,
    this.secondaryNumber = '',
    this.district = '',
    required this.city,
    this.postalCode = '',
    this.countryCode = '',
    this.additionalInfo = '',
    this.isDefault = false,
  });

  static String _s(dynamic v) => v == null ? '' : v.toString();

  factory Address.fromJson(Map<String, dynamic> j) => Address(
        id: (j['id'] as num?)?.toInt(),
        label: _s(j['label']),
        recipientName: _s(j['recipientName']),
        phone: _s(j['phone']),
        buildingNumber: _s(j['buildingNumber']),
        streetName: _s(j['streetName']),
        secondaryNumber: _s(j['secondaryNumber']),
        district: _s(j['district']),
        city: _s(j['city']),
        postalCode: _s(j['postalCode']),
        countryCode: _s(j['countryCode']),
        additionalInfo: _s(j['additionalInfo']),
        isDefault: j['isDefault'] == true,
      );

  /// Whole-address body for POST / PUT. Empty optional fields are sent as
  /// null so the server stores nothing instead of an empty string.
  Map<String, dynamic> toJson() {
    String? n(String v) => v.trim().isEmpty ? null : v.trim();
    return {
      'label': n(label),
      'recipientName': n(recipientName),
      'phone': phone.trim(),
      'buildingNumber': n(buildingNumber),
      'streetName': streetName.trim(),
      'secondaryNumber': n(secondaryNumber),
      'district': n(district),
      'city': city.trim(),
      'postalCode': n(postalCode),
      'countryCode': n(countryCode),
      'additionalInfo': n(additionalInfo),
      'isDefault': isDefault,
    };
  }

  /// One-line text for lists and the invoice.
  String get summary {
    final parts = <String>[
      if (buildingNumber.isNotEmpty || streetName.isNotEmpty)
        [buildingNumber, streetName].where((e) => e.isNotEmpty).join(' '),
      if (district.isNotEmpty) district,
      city,
      if (postalCode.isNotEmpty) postalCode,
    ];
    return parts.where((e) => e.isNotEmpty).join(', ');
  }
}

/// One entry of the quote's shippingOptions. The screen is built from
/// [available] and [reason], never from the method name, because later
/// admin rules only change those two.
class ShippingOption {
  final String method; // PICKUP | FREE_SHIPPING
  final double amount;
  final bool requiresAddress;
  final bool available;
  final String? reason;

  const ShippingOption({
    required this.method,
    required this.amount,
    required this.requiresAddress,
    required this.available,
    this.reason,
  });

  factory ShippingOption.fromJson(Map<String, dynamic> j) => ShippingOption(
        method: (j['method'] ?? '').toString(),
        amount: (j['amount'] as num?)?.toDouble() ?? 0.0,
        requiresAddress: j['requiresAddress'] == true,
        available: j['available'] == true,
        reason: j['reason']?.toString(),
      );
}
