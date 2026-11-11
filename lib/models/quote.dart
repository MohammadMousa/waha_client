import 'address.dart';

/// An offer the server applied: only its id and display name.
class AppliedOffer {
  final int id;
  final String name;

  const AppliedOffer({required this.id, required this.name});

  static AppliedOffer? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    if (id is! num) return null;
    return AppliedOffer(id: id.toInt(), name: (json['name'] ?? '').toString());
  }
}

/// The coupon the server applied: its code, name and its own share of the
/// discount (already included in the order's total discount).
class AppliedCoupon {
  final String code;
  final String name;
  final double discountAmount;

  const AppliedCoupon(
      {required this.code, required this.name, required this.discountAmount});

  static AppliedCoupon? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final code = json['code'];
    if (code == null) return null;
    return AppliedCoupon(
      code: code.toString(),
      name: (json['name'] ?? '').toString(),
      discountAmount: (json['discountAmount'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class QuoteLine {
  final int productId;
  final Map<String, dynamic> name; // {"ar": "...", "en": "..."}
  final int quantity;
  final double unitPrice;
  final double lineTotal;

  /// Server-calculated discount on this line (own offer plus its share of
  /// the invoice offer). Zero when the backend sends no offer fields.
  final double discountAmount;
  final AppliedOffer? offer;

  const QuoteLine({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.discountAmount = 0.0,
    this.offer,
  });

  factory QuoteLine.fromJson(Map<String, dynamic> json) => QuoteLine(
        productId: json['productId'] as int,
        name: (json['name'] as Map<String, dynamic>?) ?? {},
        quantity: json['quantity'] as int,
        unitPrice: (json['unitPrice'] as num).toDouble(),
        lineTotal: (json['lineTotal'] as num).toDouble(),
        discountAmount: (json['discountAmount'] as num?)?.toDouble() ?? 0.0,
        offer: AppliedOffer.fromJson(json['offer']),
      );
}

class Quote {
  final double subtotal;
  final double tax;
  final double total;
  final List<QuoteLine> items;

  /// Total discount from all offers, and the invoice-level offer if any.
  final double discountAmount;
  final AppliedOffer? invoiceOffer;
  final AppliedCoupon? coupon;

  /// Null unless this is a signed-in normal-mode session (online orders).
  final List<ShippingOption>? shippingOptions;

  const Quote({
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.items,
    this.discountAmount = 0.0,
    this.invoiceOffer,
    this.coupon,
    this.shippingOptions,
  });

  factory Quote.fromJson(Map<String, dynamic> json) => Quote(
        subtotal: (json['subtotal'] as num).toDouble(),
        tax: (json['tax'] as num).toDouble(),
        total: (json['total'] as num).toDouble(),
        items: (json['items'] as List<dynamic>)
            .map((e) => QuoteLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        discountAmount: (json['discountAmount'] as num?)?.toDouble() ?? 0.0,
        invoiceOffer: AppliedOffer.fromJson(json['invoiceOffer']),
        coupon: AppliedCoupon.fromJson(json['coupon']),
        shippingOptions: (json['shippingOptions'] as List<dynamic>?)
            ?.map((e) => ShippingOption.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
