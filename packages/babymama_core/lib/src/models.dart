// Models matching the API DTOs in backend/src/lib/dto.ts.

typedef Json = Map<String, dynamic>;

int _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
int? _intOrNull(dynamic v) => v == null ? null : _int(v);
double? _double(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
String _str(dynamic v, [String fallback = '']) => v == null ? fallback : '$v';
String? _strOrNull(dynamic v) => v == null ? null : '$v';
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
Json? _map(dynamic v) => v is Map<String, dynamic> ? v : null;
List<Json> _list(dynamic v) => v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

class Paged<T> {
  Paged({required this.items, required this.total, required this.page, required this.pages});

  factory Paged.fromJson(Json j, T Function(Json) parse) => Paged(
        items: _list(j['items']).map(parse).toList(),
        total: _int(j['total']),
        page: _int(j['page']),
        pages: _int(j['pages']),
      );

  final List<T> items;
  final int total;
  final int page;
  final int pages;

  bool get hasMore => page < pages;
}

class BmUser {
  BmUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.phone,
    this.locale = 'en',
    this.avatarUrl,
    this.isActive = true,
    this.hasPassword = true,
    this.orderCount,
  });

  factory BmUser.fromJson(Json j) => BmUser(
        id: _str(j['id']),
        name: _str(j['name']),
        email: _str(j['email']),
        role: _str(j['role'], 'CUSTOMER'),
        phone: _strOrNull(j['phone']),
        locale: _str(j['locale'], 'en'),
        avatarUrl: _strOrNull(j['avatarUrl']),
        isActive: j['isActive'] != false,
        hasPassword: j['hasPassword'] != false,
        orderCount: _intOrNull(j['orderCount']),
      );

  final String id;
  final String name;
  final String email;
  final String role;
  final String? phone;
  final String locale;
  final String? avatarUrl;
  final bool isActive;
  final bool hasPassword;
  final int? orderCount;

  bool get isAdmin => role == 'ADMIN';
  bool get isDriver => role == 'DRIVER';
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }
}

class Category {
  Category({
    required this.id,
    required this.slug,
    required this.nameEn,
    required this.nameFr,
    this.imageUrl,
    this.parentId,
    this.parent,
    this.icon,
    this.position = 0,
    this.ownSizeType,
    this.sizeType,
    this.sizes = const [],
  });

  factory Category.fromJson(Json j) => Category(
        id: _str(j['id']),
        slug: _str(j['slug']),
        nameEn: _str(j['nameEn']),
        nameFr: _str(j['nameFr']),
        imageUrl: _strOrNull(j['imageUrl']),
        parentId: _strOrNull(j['parentId']),
        parent: _map(j['parent']) == null ? null : Category.fromJson(_map(j['parent'])!),
        icon: _strOrNull(j['icon']),
        position: _int(j['position'] ?? 0),
        ownSizeType: _strOrNull(j['ownSizeType']),
        sizeType: _strOrNull(j['sizeType']),
        sizes: (j['sizes'] is List ? j['sizes'] as List : const []).map((e) => '$e').toList(),
      );

  final String id;
  final String slug;
  final String nameEn;
  final String nameFr;
  final String? imageUrl;
  final String? parentId;

  /// The department (Women, Men, Kids) for a sub-category.
  final Category? parent;

  /// Key of a [CategoryIcon] (dress, tshirt, shoe...).
  final String? icon;
  final int position;

  /// CLOTHING, KIDS_AGE, SHOES or ONE_SIZE; `sizeType` includes the one inherited from the parent.
  final String? ownSizeType;
  final String? sizeType;

  /// Sizes allowed for products of this category, in display order (empty: no size).
  final List<String> sizes;

  String name(String lang) => lang == 'fr' ? nameFr : nameEn;

  /// "Women › Dresses".
  String path(String lang) => parent == null ? name(lang) : '${parent!.name(lang)} › ${name(lang)}';
}

class Product {
  Product({
    required this.id,
    required this.sku,
    required this.title,
    required this.description,
    required this.condition,
    required this.price,
    required this.stock,
    required this.status,
    required this.images,
    required this.createdAt,
    this.brand,
    this.size,
    this.color,
    this.compareAtPrice,
    this.lowStockThreshold = 1,
    this.isFeatured = false,
    this.source = 'ADMIN',
    this.category,
    this.sellerName,
    this.isFavorite = false,
    this.rejectReason,
    this.wooId,
    this.related = const [],
    this.discountTiers = const [],
  });

  factory Product.fromJson(Json j) => Product(
        id: _str(j['id']),
        sku: _str(j['sku']),
        title: _str(j['title']),
        description: _str(j['description']),
        brand: _strOrNull(j['brand']),
        size: _strOrNull(j['size']),
        color: _strOrNull(j['color']),
        condition: _str(j['condition'], 'GOOD'),
        price: _int(j['price']),
        compareAtPrice: _intOrNull(j['compareAtPrice']),
        stock: _int(j['stock']),
        lowStockThreshold: _int(j['lowStockThreshold'] ?? 1),
        status: _str(j['status'], 'ACTIVE'),
        isFeatured: j['isFeatured'] == true,
        source: _str(j['source'], 'ADMIN'),
        images: (j['images'] is List ? j['images'] as List : const []).map((e) => '$e').toList(),
        category: _map(j['category']) == null ? null : Category.fromJson(_map(j['category'])!),
        sellerName: _strOrNull(_map(j['seller'])?['name']),
        isFavorite: j['isFavorite'] == true,
        rejectReason: _strOrNull(j['rejectReason']),
        wooId: _intOrNull(j['wooId']),
        createdAt: _date(j['createdAt']) ?? DateTime.now(),
        related: _list(j['related']).map(Product.fromJson).toList(),
        discountTiers: _list(j['discountTiers']).map(DiscountTier.fromJson).toList(),
      );

  final String id;
  final String sku;
  final String title;
  final String description;
  final String? brand;
  final String? size;
  final String? color;
  final String condition;
  final int price;
  final int? compareAtPrice;
  final int stock;
  final int lowStockThreshold;
  final String status;
  final bool isFeatured;
  final String source;
  final List<String> images;
  final Category? category;
  final String? sellerName;
  final bool isFavorite;
  final String? rejectReason;
  final int? wooId;
  final DateTime createdAt;
  final List<Product> related;
  final List<DiscountTier> discountTiers;

  String? get image => images.isEmpty ? null : images.first;
  bool get isAvailable => status == 'ACTIVE' && stock > 0;
  bool get isLowStock => stock <= lowStockThreshold;
  bool get isNew => DateTime.now().difference(createdAt).inDays < 7;
}

class DiscountTier {
  DiscountTier({required this.minItems, required this.percent, this.active = true});

  factory DiscountTier.fromJson(Json j) =>
      DiscountTier(minItems: _int(j['minItems']), percent: _int(j['percent']), active: j['active'] != false);

  final int minItems;
  final int percent;
  final bool active;

  Json toJson() => {'minItems': minItems, 'percent': percent, 'active': active};
}

class BannerSlide {
  BannerSlide({
    required this.id,
    required this.titleEn,
    required this.titleFr,
    required this.imageUrl,
    required this.type,
    this.subtitleEn,
    this.subtitleFr,
    this.targetId,
    this.url,
    this.position = 0,
    this.active = true,
    this.startsAt,
    this.endsAt,
  });

  factory BannerSlide.fromJson(Json j) => BannerSlide(
        id: _str(j['id']),
        titleEn: _str(j['titleEn']),
        titleFr: _str(j['titleFr']),
        subtitleEn: _strOrNull(j['subtitleEn']),
        subtitleFr: _strOrNull(j['subtitleFr']),
        imageUrl: _str(j['imageUrl']),
        type: _str(j['type'], 'PROMO'),
        targetId: _strOrNull(j['targetId']),
        url: _strOrNull(j['url']),
        position: _int(j['position']),
        active: j['active'] != false,
        startsAt: _date(j['startsAt']),
        endsAt: _date(j['endsAt']),
      );

  final String id;
  final String titleEn;
  final String titleFr;
  final String? subtitleEn;
  final String? subtitleFr;
  final String imageUrl;
  final String type;
  final String? targetId;
  final String? url;
  final int position;
  final bool active;
  final DateTime? startsAt;
  final DateTime? endsAt;

  String title(String lang) => lang == 'fr' ? titleFr : titleEn;
  String? subtitle(String lang) => lang == 'fr' ? subtitleFr : subtitleEn;
}

class BundleItem {
  BundleItem({required this.productId, required this.quantity, required this.product});

  factory BundleItem.fromJson(Json j) => BundleItem(
        productId: _str(j['productId']),
        quantity: _int(j['quantity']),
        product: Product.fromJson(_map(j['product']) ?? const {}),
      );

  final String productId;
  final int quantity;
  final Product product;
}

/// Bundle sale ("vente groupée" / lot).
class Bundle {
  Bundle({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.originalPrice,
    required this.available,
    required this.items,
    this.titleFr,
    this.imageUrl,
    this.active = true,
  });

  factory Bundle.fromJson(Json j) => Bundle(
        id: _str(j['id']),
        title: _str(j['title']),
        titleFr: _strOrNull(j['titleFr']),
        description: _str(j['description']),
        price: _int(j['price']),
        originalPrice: _int(j['originalPrice']),
        available: _int(j['available']),
        imageUrl: _strOrNull(j['imageUrl']),
        active: j['active'] != false,
        items: _list(j['items']).map(BundleItem.fromJson).toList(),
      );

  final String id;
  final String title;
  final String? titleFr;
  final String description;
  final int price;
  final int originalPrice;
  final int available;
  final String? imageUrl;
  final bool active;
  final List<BundleItem> items;

  String localizedTitle(String lang) => lang == 'fr' && (titleFr?.isNotEmpty ?? false) ? titleFr! : title;
  int get savingPercent => originalPrice <= 0 ? 0 : (((originalPrice - price) / originalPrice) * 100).round();
}

class DeliveryZone {
  DeliveryZone({required this.id, required this.name, required this.fee, required this.etaMinutes, this.active = true, this.position = 0});

  factory DeliveryZone.fromJson(Json j) => DeliveryZone(
        id: _str(j['id']),
        name: _str(j['name']),
        fee: _int(j['fee']),
        etaMinutes: _int(j['etaMinutes']),
        active: j['active'] != false,
        position: _int(j['position']),
      );

  final String id;
  final String name;
  final int fee;
  final int etaMinutes;
  final bool active;
  final int position;
}

class HomeFeed {
  HomeFeed({
    required this.banners,
    required this.categories,
    required this.newArrivals,
    required this.featured,
    required this.bundles,
    required this.discountTiers,
  });

  factory HomeFeed.fromJson(Json j) => HomeFeed(
        banners: _list(j['banners']).map(BannerSlide.fromJson).toList(),
        categories: _list(j['categories']).map(Category.fromJson).toList(),
        newArrivals: _list(j['newArrivals']).map(Product.fromJson).toList(),
        featured: _list(j['featured']).map(Product.fromJson).toList(),
        bundles: _list(j['bundles']).map(Bundle.fromJson).toList(),
        discountTiers: _list(j['discountTiers']).map(DiscountTier.fromJson).toList(),
      );

  final List<BannerSlide> banners;
  final List<Category> categories;
  final List<Product> newArrivals;
  final List<Product> featured;
  final List<Bundle> bundles;
  final List<DiscountTier> discountTiers;
}

class QuoteLine {
  QuoteLine({required this.kind, required this.title, required this.unitPrice, required this.quantity, required this.available, this.productId, this.bundleId, this.imageUrl});

  factory QuoteLine.fromJson(Json j) => QuoteLine(
        kind: _str(j['kind']),
        productId: _strOrNull(j['productId']),
        bundleId: _strOrNull(j['bundleId']),
        title: _str(j['title']),
        imageUrl: _strOrNull(j['imageUrl']),
        unitPrice: _int(j['unitPrice']),
        quantity: _int(j['quantity']),
        available: _int(j['available']),
      );

  final String kind;
  final String? productId;
  final String? bundleId;
  final String title;
  final String? imageUrl;
  final int unitPrice;
  final int quantity;
  final int available;
}

class Quote {
  Quote({
    required this.subtotal,
    required this.discount,
    required this.discountPercent,
    required this.deliveryFee,
    required this.total,
    required this.itemCount,
    required this.lines,
    this.nextTier,
  });

  factory Quote.fromJson(Json j) => Quote(
        subtotal: _int(j['subtotal']),
        discount: _int(j['discount']),
        discountPercent: _int(j['discountPercent']),
        deliveryFee: _int(j['deliveryFee']),
        total: _int(j['total']),
        itemCount: _int(j['itemCount']),
        nextTier: _map(j['nextTier']) == null ? null : DiscountTier.fromJson(_map(j['nextTier'])!),
        lines: _list(j['lines']).map(QuoteLine.fromJson).toList(),
      );

  final int subtotal;
  final int discount;
  final int discountPercent;
  final int deliveryFee;
  final int total;
  final int itemCount;
  final DiscountTier? nextTier;
  final List<QuoteLine> lines;
}

class OrderItem {
  OrderItem({required this.id, required this.title, required this.unitPrice, required this.quantity, this.productId, this.bundleId, this.imageUrl});

  factory OrderItem.fromJson(Json j) => OrderItem(
        id: _str(j['id']),
        productId: _strOrNull(j['productId']),
        bundleId: _strOrNull(j['bundleId']),
        title: _str(j['title']),
        imageUrl: _strOrNull(j['imageUrl']),
        unitPrice: _int(j['unitPrice']),
        quantity: _int(j['quantity']),
      );

  final String id;
  final String? productId;
  final String? bundleId;
  final String title;
  final String? imageUrl;
  final int unitPrice;
  final int quantity;
}

class PersonRef {
  PersonRef({required this.id, required this.name, this.phone, this.email});

  static PersonRef? fromJson(dynamic v) {
    final j = _map(v);
    if (j == null) return null;
    return PersonRef(id: _str(j['id']), name: _str(j['name']), phone: _strOrNull(j['phone']), email: _strOrNull(j['email']));
  }

  final String id;
  final String name;
  final String? phone;
  final String? email;
}

class DeliveryInfo {
  DeliveryInfo({
    required this.id,
    required this.status,
    this.driver,
    this.assignedAt,
    this.pickedUpAt,
    this.deliveredAt,
    this.failedReason,
    this.lastLat,
    this.lastLng,
    this.lastLocationAt,
  });

  factory DeliveryInfo.fromJson(Json j) => DeliveryInfo(
        id: _str(j['id']),
        status: _str(j['status'], 'UNASSIGNED'),
        driver: PersonRef.fromJson(j['driver']),
        assignedAt: _date(j['assignedAt']),
        pickedUpAt: _date(j['pickedUpAt']),
        deliveredAt: _date(j['deliveredAt']),
        failedReason: _strOrNull(j['failedReason']),
        lastLat: _double(j['lastLat']),
        lastLng: _double(j['lastLng']),
        lastLocationAt: _date(j['lastLocationAt']),
      );

  final String id;
  final String status;
  final PersonRef? driver;
  final DateTime? assignedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final String? failedReason;
  final double? lastLat;
  final double? lastLng;
  final DateTime? lastLocationAt;
}

class Review {
  Review({required this.rating, this.comment, this.driverRating, this.createdAt});

  factory Review.fromJson(Json j) => Review(
        rating: _int(j['rating']),
        comment: _strOrNull(j['comment']),
        driverRating: _intOrNull(j['driverRating']),
        createdAt: _date(j['createdAt']),
      );

  final int rating;
  final String? comment;
  final int? driverRating;
  final DateTime? createdAt;
}

class Order {
  Order({
    required this.id,
    required this.number,
    required this.status,
    required this.paymentStatus,
    required this.paymentMethod,
    required this.subtotal,
    required this.discount,
    required this.discountPercent,
    required this.deliveryFee,
    required this.total,
    required this.amountToCollect,
    required this.address,
    required this.zoneName,
    required this.items,
    required this.createdAt,
    this.etaMinutes = 90,
    this.notes,
    this.deliveryCode,
    this.expiresAt,
    this.cancelReason,
    this.customer,
    this.delivery,
    this.review,
  });

  factory Order.fromJson(Json j) => Order(
        id: _str(j['id']),
        number: _str(j['number']),
        status: _str(j['status']),
        paymentStatus: _str(j['paymentStatus']),
        paymentMethod: _str(j['paymentMethod']),
        subtotal: _int(j['subtotal']),
        discount: _int(j['discount']),
        discountPercent: _int(j['discountPercent']),
        deliveryFee: _int(j['deliveryFee']),
        total: _int(j['total']),
        amountToCollect: _int(j['amountToCollect']),
        address: _map(j['address']) ?? const {},
        zoneName: _str(_map(j['zone'])?['name']),
        etaMinutes: _int(_map(j['zone'])?['etaMinutes'] ?? 90),
        notes: _strOrNull(j['notes']),
        deliveryCode: _strOrNull(j['deliveryCode']),
        expiresAt: _date(j['expiresAt']),
        cancelReason: _strOrNull(j['cancelReason']),
        createdAt: _date(j['createdAt']) ?? DateTime.now(),
        customer: PersonRef.fromJson(j['customer']),
        items: _list(j['items']).map(OrderItem.fromJson).toList(),
        delivery: _map(j['delivery']) == null ? null : DeliveryInfo.fromJson(_map(j['delivery'])!),
        review: _map(j['review']) == null ? null : Review.fromJson(_map(j['review'])!),
      );

  final String id;
  final String number;
  final String status;
  final String paymentStatus;
  final String paymentMethod;
  final int subtotal;
  final int discount;
  final int discountPercent;
  final int deliveryFee;
  final int total;
  final int amountToCollect;
  final Json address;
  final String zoneName;
  final int etaMinutes;
  final String? notes;
  final String? deliveryCode;
  final DateTime? expiresAt;
  final String? cancelReason;
  final DateTime createdAt;
  final PersonRef? customer;
  final List<OrderItem> items;
  final DeliveryInfo? delivery;
  final Review? review;

  bool get canPay => status == 'PENDING_PAYMENT' && paymentStatus != 'PAID';
  bool get canCancel => status == 'PENDING_PAYMENT' || status == 'CONFIRMED';
  bool get canReview => status == 'DELIVERED' && review == null;
  int get itemCount => items.fold(0, (s, i) => s + i.quantity);

  String get recipientName => _str(address['recipientName']);
  String get phone => _str(address['phone']);
  String get street => _str(address['street']);
  String? get landmark => _strOrNull(address['landmark']);
  double? get lat => _double(address['lat']);
  double? get lng => _double(address['lng']);
}

class PaymentAttempt {
  PaymentAttempt({required this.id, required this.status, required this.method, required this.amount, this.message, this.redirectUrl, this.receipt});

  factory PaymentAttempt.fromJson(Json j) => PaymentAttempt(
        id: _str(j['id']),
        status: _str(j['status']),
        method: _str(j['method']),
        amount: _int(j['amount']),
        message: _strOrNull(j['message']),
        redirectUrl: _strOrNull(j['redirectUrl']),
        receipt: _strOrNull(j['receipt']),
      );

  final String id;
  final String status;
  final String method;
  final int amount;
  final String? message;
  final String? redirectUrl;
  final String? receipt;
}

class PaymentOption {
  PaymentOption({required this.method, required this.name, required this.simulated});

  factory PaymentOption.fromJson(Json j) =>
      PaymentOption(method: _str(j['method']), name: _str(j['name']), simulated: j['simulated'] == true);

  final String method;
  final String name;
  final bool simulated;
}

class TicketMessage {
  TicketMessage({required this.id, required this.body, required this.isStaff, required this.senderName, required this.createdAt});

  factory TicketMessage.fromJson(Json j) => TicketMessage(
        id: _str(j['id']),
        body: _str(j['body']),
        isStaff: j['isStaff'] == true,
        senderName: _str(j['senderName']),
        createdAt: _date(j['createdAt']) ?? DateTime.now(),
      );

  final String id;
  final String body;
  final bool isStaff;
  final String senderName;
  final DateTime createdAt;
}

class SupportTicket {
  SupportTicket({
    required this.id,
    required this.subject,
    required this.status,
    required this.updatedAt,
    required this.messages,
    this.orderId,
    this.orderNumber,
    this.user,
    this.lastMessage,
  });

  factory SupportTicket.fromJson(Json j) => SupportTicket(
        id: _str(j['id']),
        subject: _str(j['subject']),
        status: _str(j['status']),
        orderId: _strOrNull(j['orderId']),
        orderNumber: _strOrNull(j['orderNumber']),
        updatedAt: _date(j['updatedAt']) ?? DateTime.now(),
        user: PersonRef.fromJson(j['user']),
        lastMessage: _strOrNull(_map(j['lastMessage'])?['body']),
        messages: _list(j['messages']).map(TicketMessage.fromJson).toList(),
      );

  final String id;
  final String subject;
  final String status;
  final String? orderId;
  final String? orderNumber;
  final DateTime updatedAt;
  final PersonRef? user;
  final String? lastMessage;
  final List<TicketMessage> messages;
}

/// A delivery as seen by the rider app.
class DriverDelivery {
  DriverDelivery({required this.id, required this.status, required this.order, this.failedReason, this.deliveredAt, this.cashCollected});

  factory DriverDelivery.fromJson(Json j) => DriverDelivery(
        id: _str(j['id']),
        status: _str(j['status']),
        failedReason: _strOrNull(j['failedReason']),
        deliveredAt: _date(j['deliveredAt']),
        cashCollected: _intOrNull(j['cashCollected']),
        order: Order.fromJson(_map(j['order']) ?? const {}),
      );

  final String id;
  final String status;
  final String? failedReason;
  final DateTime? deliveredAt;
  final int? cashCollected;
  final Order order;
}
