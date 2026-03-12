// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'localDatabase.dart';

// **************************************************************************
// MoorGenerator
// **************************************************************************

// ignore_for_file: type=lint
class CartProduct extends DataClass implements Insertable<CartProduct> {
  final String id;
  final String? category_id;
  final String name;
  final String photo;
  final String price;
  final String? discountPrice;
  final String vendorID;
  final int quantity;
  final String? extras_price;
  final dynamic extras;
  final String? bundleId;
  final String? bundleName;
  final String? addonPromoId;
  final String? addonPromoName;
  final DateTime addedAt;
  final DateTime? lastModifiedAt;
  final dynamic variant_info;
  CartProduct({
    required this.id,
    this.category_id,
    required this.name,
    required this.photo,
    required this.price,
    this.discountPrice,
    required this.vendorID,
    required this.quantity,
    this.extras_price,
    this.extras,
    this.bundleId,
    this.bundleName,
    this.addonPromoId,
    this.addonPromoName,
    required this.addedAt,
    this.lastModifiedAt,
    this.variant_info,
  });
  factory CartProduct.fromData(Map<String, dynamic> data, GeneratedDatabase db,
      {String? prefix}) {
    final effectivePrefix = prefix ?? '';
    return CartProduct(
      id: const StringType()
          .mapFromDatabaseResponse(data['${effectivePrefix}id'])!,
      category_id: const StringType()
          .mapFromDatabaseResponse(data['${effectivePrefix}category_id']),
      name: const StringType()
          .mapFromDatabaseResponse(data['${effectivePrefix}name'])!,
      photo: const StringType()
          .mapFromDatabaseResponse(data['${effectivePrefix}photo'])!,
      price: const StringType()
          .mapFromDatabaseResponse(data['${effectivePrefix}price'])!,
      discountPrice: const StringType()
          .mapFromDatabaseResponse(data['${effectivePrefix}discount_price']),
      vendorID: const StringType()
          .mapFromDatabaseResponse(data['${effectivePrefix}vendor_i_d'])!,
      quantity: const IntType()
          .mapFromDatabaseResponse(data['${effectivePrefix}quantity'])!,
      extras_price: const StringType()
          .mapFromDatabaseResponse(data['${effectivePrefix}extras_price']),
      extras: const StringType()
          .mapFromDatabaseResponse(data['${effectivePrefix}extras']),
      bundleId: const StringType()
          .mapFromDatabaseResponse(data['${effectivePrefix}bundle_id']),
      bundleName: const StringType()
          .mapFromDatabaseResponse(data['${effectivePrefix}bundle_name']),
      addonPromoId: const StringType()
          .mapFromDatabaseResponse(data['${effectivePrefix}addon_promo_id']),
      addonPromoName: const StringType()
          .mapFromDatabaseResponse(data['${effectivePrefix}addon_promo_name']),
      addedAt: const DateTimeType()
          .mapFromDatabaseResponse(data['${effectivePrefix}added_at'])!,
      lastModifiedAt: const DateTimeType()
          .mapFromDatabaseResponse(data['${effectivePrefix}last_modified_at']),
      variant_info: const StringType()
          .mapFromDatabaseResponse(data['${effectivePrefix}variant_info']),
    );
  }
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || category_id != null) {
      map['category_id'] = Variable<String?>(category_id);
    }
    map['name'] = Variable<String>(name);
    map['photo'] = Variable<String>(photo);
    map['price'] = Variable<String>(price);
    if (!nullToAbsent || discountPrice != null) {
      map['discount_price'] = Variable<String?>(discountPrice);
    }
    map['vendor_i_d'] = Variable<String>(vendorID);
    map['quantity'] = Variable<int>(quantity);
    if (!nullToAbsent || extras_price != null) {
      map['extras_price'] = Variable<String?>(extras_price);
    }
    if (!nullToAbsent || extras != null) {
      map['extras'] = Variable<String?>(jsonEncode(extras));
    }
    if (!nullToAbsent || variant_info != null) {
      map['variant_info'] = Variable<String?>(jsonEncode(variant_info));
    }
    if (!nullToAbsent || bundleId != null) {
      map['bundle_id'] = Variable<String?>(bundleId);
    }
    if (!nullToAbsent || bundleName != null) {
      map['bundle_name'] = Variable<String?>(bundleName);
    }
    if (!nullToAbsent || addonPromoId != null) {
      map['addon_promo_id'] = Variable<String?>(addonPromoId);
    }
    if (!nullToAbsent || addonPromoName != null) {
      map['addon_promo_name'] = Variable<String?>(addonPromoName);
    }
    map['added_at'] = Variable<DateTime>(addedAt);
    if (!nullToAbsent || lastModifiedAt != null) {
      map['last_modified_at'] = Variable<DateTime?>(lastModifiedAt);
    }
    return map;
  }

  CartProductsCompanion toCompanion(bool nullToAbsent) {
    return CartProductsCompanion(
      id: Value(id),
      category_id: category_id == null && nullToAbsent
          ? const Value.absent()
          : Value(category_id),
      name: Value(name),
      photo: Value(photo),
      price: Value(price),
      discountPrice: discountPrice == null && nullToAbsent
          ? const Value.absent()
          : Value(discountPrice),
      vendorID: Value(vendorID),
      quantity: Value(quantity),
      extras_price: extras_price == null && nullToAbsent
          ? const Value.absent()
          : Value(extras_price),
      extras:
          extras == null && nullToAbsent ? const Value.absent() : Value(extras),
      variant_info: variant_info == null && nullToAbsent
          ? const Value.absent()
          : Value(variant_info),
      bundleId: bundleId == null && nullToAbsent
          ? const Value.absent()
          : Value(bundleId),
      bundleName: bundleName == null && nullToAbsent
          ? const Value.absent()
          : Value(bundleName),
      addonPromoId: addonPromoId == null && nullToAbsent
          ? const Value.absent()
          : Value(addonPromoId),
      addonPromoName: addonPromoName == null && nullToAbsent
          ? const Value.absent()
          : Value(addonPromoName),
      addedAt: Value(addedAt),
      lastModifiedAt: lastModifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastModifiedAt),
    );
  }

  factory CartProduct.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= moorRuntimeOptions.defaultSerializer;
    DateTime? addedAtVal;
    try {
      addedAtVal = json['addedAt'] != null
          ? DateTime.tryParse(json['addedAt'].toString()) ?? DateTime.now()
          : DateTime.now();
    } catch (_) {
      addedAtVal = DateTime.now();
    }
    return CartProduct(
      id: serializer.fromJson<String>(json['id']),
      category_id: serializer.fromJson<String?>(json['category_id']),
      name: serializer.fromJson<String>(json['name']),
      photo: serializer.fromJson<String>(json['photo']),
      price: serializer.fromJson<String>(json['price']),
      discountPrice: serializer.fromJson<String?>(json['discountPrice']),
      vendorID: serializer.fromJson<String>(json['vendorID']),
      quantity: serializer.fromJson<int>(json['quantity']),
      extras_price: serializer.fromJson<String?>(json['extras_price']),
      extras: json['extras'],
      bundleId: serializer.fromJson<String?>(json['bundleId']),
      bundleName: serializer.fromJson<String?>(json['bundleName']),
      addonPromoId: serializer.fromJson<String?>(json['addonPromoId']),
      addonPromoName: serializer.fromJson<String?>(json['addonPromoName']),
      addedAt: addedAtVal,
      lastModifiedAt: json['lastModifiedAt'] != null
          ? DateTime.tryParse(json['lastModifiedAt'].toString())
          : null,
      variant_info: json['variant_info'],
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= moorRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'category_id': serializer.toJson<String?>(category_id),
      'name': serializer.toJson<String>(name),
      'photo': serializer.toJson<String>(photo),
      'price': serializer.toJson<String>(price),
      'discountPrice': serializer.toJson<String?>(discountPrice),
      'vendorID': serializer.toJson<String>(vendorID),
      'quantity': serializer.toJson<int>(quantity),
      'extras_price': serializer.toJson<String?>(extras_price),
      'extras': extras,
      'bundleId': serializer.toJson<String?>(bundleId),
      'bundleName': serializer.toJson<String?>(bundleName),
      'addonPromoId': serializer.toJson<String?>(addonPromoId),
      'addonPromoName': serializer.toJson<String?>(addonPromoName),
      'addedAt': addedAt.toIso8601String(),
      'lastModifiedAt': lastModifiedAt?.toIso8601String(),
      'variant_info': variant_info,
    };
  }

  CartProduct copyWith(
          {String? id,
          String? category_id,
          String? name,
          String? photo,
          String? price,
          String? discountPrice,
          String? vendorID,
          int? quantity,
          String? extras_price,
          dynamic extras,
          String? bundleId,
          String? bundleName,
          String? addonPromoId,
          String? addonPromoName,
          DateTime? addedAt,
          DateTime? lastModifiedAt,
          dynamic variant_info}) =>
      CartProduct(
        id: id ?? this.id,
        category_id: category_id ?? this.category_id,
        name: name ?? this.name,
        photo: photo ?? this.photo,
        price: price ?? this.price,
        discountPrice: discountPrice ?? this.discountPrice,
        vendorID: vendorID ?? this.vendorID,
        quantity: quantity ?? this.quantity,
        extras_price: extras_price ?? this.extras_price,
        extras: extras ?? this.extras,
        bundleId: bundleId ?? this.bundleId,
        bundleName: bundleName ?? this.bundleName,
        addonPromoId: addonPromoId ?? this.addonPromoId,
        addonPromoName: addonPromoName ?? this.addonPromoName,
        addedAt: addedAt ?? this.addedAt,
        lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
        variant_info: variant_info ?? this.variant_info,
      );
  @override
  String toString() {
    return (StringBuffer('CartProduct(')
          ..write('id: $id, ')
          ..write('category_id: $category_id, ')
          ..write('name: $name, ')
          ..write('photo: $photo, ')
          ..write('price: $price, ')
          ..write('discountPrice: $discountPrice, ')
          ..write('vendorID: $vendorID, ')
          ..write('quantity: $quantity, ')
          ..write('extras_price: $extras_price, ')
          ..write('extras: $extras, ')
          ..write('bundleId: $bundleId, ')
          ..write('bundleName: $bundleName, ')
          ..write('addonPromoId: $addonPromoId, ')
          ..write('addonPromoName: $addonPromoName, ')
          ..write('addedAt: $addedAt, ')
          ..write('lastModifiedAt: $lastModifiedAt, ')
          ..write('variant_info: $variant_info')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      category_id,
      name,
      photo,
      price,
      discountPrice,
      vendorID,
      quantity,
      extras_price,
      extras,
      bundleId,
      bundleName,
      addonPromoId,
      addonPromoName,
      addedAt,
      lastModifiedAt,
      variant_info);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CartProduct &&
          other.id == this.id &&
          other.category_id == this.category_id &&
          other.name == this.name &&
          other.photo == this.photo &&
          other.price == this.price &&
          other.discountPrice == this.discountPrice &&
          other.vendorID == this.vendorID &&
          other.quantity == this.quantity &&
          other.extras_price == this.extras_price &&
          other.extras == this.extras &&
          other.bundleId == this.bundleId &&
          other.bundleName == this.bundleName &&
          other.addonPromoId == this.addonPromoId &&
          other.addonPromoName == this.addonPromoName &&
          other.addedAt == this.addedAt &&
          other.lastModifiedAt == this.lastModifiedAt &&
          other.variant_info == this.variant_info);
}

class CartProductsCompanion extends UpdateCompanion<CartProduct> {
  final Value<String> id;
  final Value<String?> category_id;
  final Value<String> name;
  final Value<String> photo;
  final Value<String> price;
  final Value<String?> discountPrice;
  final Value<String> vendorID;
  final Value<int> quantity;
  final Value<String?> extras_price;
  final Value<String?> extras;
  final Value<String?> bundleId;
  final Value<String?> bundleName;
  final Value<String?> addonPromoId;
  final Value<String?> addonPromoName;
  final Value<DateTime> addedAt;
  final Value<DateTime?> lastModifiedAt;
  final Value<dynamic> variant_info;
  const CartProductsCompanion({
    this.id = const Value.absent(),
    this.category_id = const Value.absent(),
    this.name = const Value.absent(),
    this.photo = const Value.absent(),
    this.price = const Value.absent(),
    this.discountPrice = const Value.absent(),
    this.vendorID = const Value.absent(),
    this.quantity = const Value.absent(),
    this.extras_price = const Value.absent(),
    this.extras = const Value.absent(),
    this.bundleId = const Value.absent(),
    this.bundleName = const Value.absent(),
    this.addonPromoId = const Value.absent(),
    this.addonPromoName = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.lastModifiedAt = const Value.absent(),
    this.variant_info = const Value.absent(),
  });
  CartProductsCompanion.insert({
    required String id,
    this.category_id = const Value.absent(),
    required String name,
    required String photo,
    required String price,
    this.discountPrice = const Value.absent(),
    required String vendorID,
    required int quantity,
    this.extras_price = const Value.absent(),
    this.extras = const Value.absent(),
    this.bundleId = const Value.absent(),
    this.bundleName = const Value.absent(),
    this.addonPromoId = const Value.absent(),
    this.addonPromoName = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.lastModifiedAt = const Value.absent(),
    this.variant_info = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        photo = Value(photo),
        price = Value(price),
        vendorID = Value(vendorID),
        quantity = Value(quantity);
  static Insertable<CartProduct> custom({
    Expression<String>? id,
    Expression<String?>? category_id,
    Expression<String>? name,
    Expression<String>? photo,
    Expression<String>? price,
    Expression<String?>? discountPrice,
    Expression<String>? vendorID,
    Expression<int>? quantity,
    Expression<String?>? extras_price,
    Expression<String?>? extras,
    Expression<String?>? bundleId,
    Expression<String?>? bundleName,
    Expression<String?>? addonPromoId,
    Expression<String?>? addonPromoName,
    Expression<DateTime>? addedAt,
    Expression<DateTime?>? lastModifiedAt,
    Expression<String?>? variant_info,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (category_id != null) 'category_id': category_id,
      if (name != null) 'name': name,
      if (photo != null) 'photo': photo,
      if (price != null) 'price': price,
      if (discountPrice != null) 'discount_price': discountPrice,
      if (vendorID != null) 'vendor_i_d': vendorID,
      if (quantity != null) 'quantity': quantity,
      if (extras_price != null) 'extras_price': extras_price,
      if (extras != null) 'extras': extras,
      if (bundleId != null) 'bundle_id': bundleId,
      if (bundleName != null) 'bundle_name': bundleName,
      if (addonPromoId != null) 'addon_promo_id': addonPromoId,
      if (addonPromoName != null) 'addon_promo_name': addonPromoName,
      if (addedAt != null) 'added_at': addedAt,
      if (lastModifiedAt != null) 'last_modified_at': lastModifiedAt,
      if (variant_info != null) 'variant_info': variant_info,
    });
  }

  CartProductsCompanion copyWith(
      {Value<String>? id,
      Value<String?>? category_id,
      Value<String>? name,
      Value<String>? photo,
      Value<String>? price,
      Value<String?>? discountPrice,
      Value<String>? vendorID,
      Value<int>? quantity,
      Value<String?>? extras_price,
      Value<String?>? extras,
      Value<String?>? bundleId,
      Value<String?>? bundleName,
      Value<String?>? addonPromoId,
      Value<String?>? addonPromoName,
      Value<DateTime>? addedAt,
      Value<DateTime?>? lastModifiedAt,
      Value<dynamic>? variant_info}) {
    return CartProductsCompanion(
      id: id ?? this.id,
      category_id: category_id ?? this.category_id,
      name: name ?? this.name,
      photo: photo ?? this.photo,
      price: price ?? this.price,
      discountPrice: discountPrice ?? this.discountPrice,
      vendorID: vendorID ?? this.vendorID,
      quantity: quantity ?? this.quantity,
      extras_price: extras_price ?? this.extras_price,
      extras: extras ?? this.extras,
      bundleId: bundleId ?? this.bundleId,
      bundleName: bundleName ?? this.bundleName,
      addonPromoId: addonPromoId ?? this.addonPromoId,
      addonPromoName: addonPromoName ?? this.addonPromoName,
      addedAt: addedAt ?? this.addedAt,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      variant_info: variant_info ?? this.variant_info,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (category_id.present) {
      map['category_id'] = Variable<String?>(category_id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (photo.present) {
      map['photo'] = Variable<String>(photo.value);
    }
    if (price.present) {
      map['price'] = Variable<String>(price.value);
    }
    if (discountPrice.present) {
      map['discount_price'] = Variable<String?>(discountPrice.value);
    }
    if (vendorID.present) {
      map['vendor_i_d'] = Variable<String>(vendorID.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<int>(quantity.value);
    }
    if (extras_price.present) {
      map['extras_price'] = Variable<String?>(extras_price.value);
    }
    if (extras.present) {
      map['extras'] = Variable<String?>(extras.value);
    }
    if (variant_info.present) {
      map['variant_info'] = Variable<String?>(jsonEncode(variant_info.value));
    }
    if (bundleId.present) {
      map['bundle_id'] = Variable<String?>(bundleId.value);
    }
    if (bundleName.present) {
      map['bundle_name'] = Variable<String?>(bundleName.value);
    }
    if (addonPromoId.present) {
      map['addon_promo_id'] = Variable<String?>(addonPromoId.value);
    }
    if (addonPromoName.present) {
      map['addon_promo_name'] = Variable<String?>(addonPromoName.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (lastModifiedAt.present) {
      map['last_modified_at'] = Variable<DateTime?>(lastModifiedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CartProductsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('photo: $photo, ')
          ..write('price: $price, ')
          ..write('discountPrice: $discountPrice, ')
          ..write('vendorID: $vendorID, ')
          ..write('quantity: $quantity, ')
          ..write('extras_price: $extras_price, ')
          ..write('extras: $extras, ')
          ..write('bundleId: $bundleId, ')
          ..write('bundleName: $bundleName, ')
          ..write('addonPromoId: $addonPromoId, ')
          ..write('addonPromoName: $addonPromoName, ')
          ..write('addedAt: $addedAt, ')
          ..write('lastModifiedAt: $lastModifiedAt')
          ..write(')'))
        .toString();
  }
}

class $CartProductsTable extends CartProducts
    with TableInfo<$CartProductsTable, CartProduct> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CartProductsTable(this.attachedDatabase, [this._alias]);
  final VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String?> id = GeneratedColumn<String?>(
      'id', aliasedName, false,
      type: const StringType(), requiredDuringInsert: true);
  final VerificationMeta _categoryIdMeta = const VerificationMeta('category_id');
  @override
  late final GeneratedColumn<String?> category_id = GeneratedColumn<String?>(
      'category_id', aliasedName, true,
      type: const StringType(), requiredDuringInsert: false);
  final VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String?> name = GeneratedColumn<String?>(
      'name', aliasedName, false,
      additionalChecks: GeneratedColumn.checkTextLength(maxTextLength: 50),
      type: const StringType(),
      requiredDuringInsert: true);
  final VerificationMeta _photoMeta = const VerificationMeta('photo');
  @override
  late final GeneratedColumn<String?> photo = GeneratedColumn<String?>(
      'photo', aliasedName, false,
      type: const StringType(), requiredDuringInsert: true);
  final VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<String?> price = GeneratedColumn<String?>(
      'price', aliasedName, false,
      type: const StringType(), requiredDuringInsert: true);
  final VerificationMeta _discountPriceMeta =
      const VerificationMeta('discountPrice');
  @override
  late final GeneratedColumn<String?> discountPrice = GeneratedColumn<String?>(
      'discount_price', aliasedName, true,
      type: const StringType(), requiredDuringInsert: false);
  final VerificationMeta _vendorIDMeta = const VerificationMeta('vendorID');
  @override
  late final GeneratedColumn<String?> vendorID = GeneratedColumn<String?>(
      'vendor_i_d', aliasedName, false,
      type: const StringType(), requiredDuringInsert: true);
  final VerificationMeta _quantityMeta = const VerificationMeta('quantity');
  @override
  late final GeneratedColumn<int?> quantity = GeneratedColumn<int?>(
      'quantity', aliasedName, false,
      type: const IntType(), requiredDuringInsert: true);
  final VerificationMeta _extras_priceMeta =
      const VerificationMeta('extras_price');
  @override
  late final GeneratedColumn<String?> extras_price = GeneratedColumn<String?>(
      'extras_price', aliasedName, true,
      type: const StringType(), requiredDuringInsert: false);
  final VerificationMeta _extrasMeta = const VerificationMeta('extras');
  @override
  late final GeneratedColumn<String?> extras = GeneratedColumn<String?>(
      'extras', aliasedName, true,
      type: const StringType(), requiredDuringInsert: false);
  final VerificationMeta _variantInfoMeta = const VerificationMeta('variant_info');
  @override
  late final GeneratedColumn<String?> variant_info = GeneratedColumn<String?>(
      'variant_info', aliasedName, true,
      type: const StringType(), requiredDuringInsert: false);
  final VerificationMeta _bundleIdMeta = const VerificationMeta('bundleId');
  @override
  late final GeneratedColumn<String?> bundleId = GeneratedColumn<String?>(
      'bundle_id', aliasedName, true,
      type: const StringType(), requiredDuringInsert: false);
  final VerificationMeta _bundleNameMeta = const VerificationMeta('bundleName');
  @override
  late final GeneratedColumn<String?> bundleName = GeneratedColumn<String?>(
      'bundle_name', aliasedName, true,
      type: const StringType(), requiredDuringInsert: false);
  final VerificationMeta _addonPromoIdMeta =
      const VerificationMeta('addonPromoId');
  @override
  late final GeneratedColumn<String?> addonPromoId = GeneratedColumn<String?>(
      'addon_promo_id', aliasedName, true,
      type: const StringType(), requiredDuringInsert: false);
  final VerificationMeta _addonPromoNameMeta =
      const VerificationMeta('addonPromoName');
  @override
  late final GeneratedColumn<String?> addonPromoName = GeneratedColumn<String?>(
      'addon_promo_name', aliasedName, true,
      type: const StringType(), requiredDuringInsert: false);
  final VerificationMeta _addedAtMeta = const VerificationMeta('addedAt');
  @override
  late final GeneratedColumn<DateTime?> addedAt = GeneratedColumn<DateTime?>(
      'added_at', aliasedName, false,
      type: const IntType(),
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  final VerificationMeta _lastModifiedAtMeta =
      const VerificationMeta('lastModifiedAt');
  @override
  late final GeneratedColumn<DateTime?> lastModifiedAt =
      GeneratedColumn<DateTime?>('last_modified_at', aliasedName, true,
          type: const IntType(), requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        category_id,
        name,
        photo,
        price,
        discountPrice,
        vendorID,
        quantity,
        extras_price,
        extras,
        variant_info,
        bundleId,
        bundleName,
        addonPromoId,
        addonPromoName,
        addedAt,
        lastModifiedAt
      ];
  @override
  String get aliasedName => _alias ?? 'cart_products';
  @override
  String get actualTableName => 'cart_products';
  @override
  VerificationContext validateIntegrity(Insertable<CartProduct> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
          _categoryIdMeta,
          category_id.isAcceptableOrUnknown(
              data['category_id']!, _categoryIdMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('photo')) {
      context.handle(
          _photoMeta, photo.isAcceptableOrUnknown(data['photo']!, _photoMeta));
    } else if (isInserting) {
      context.missing(_photoMeta);
    }
    if (data.containsKey('price')) {
      context.handle(
          _priceMeta, price.isAcceptableOrUnknown(data['price']!, _priceMeta));
    } else if (isInserting) {
      context.missing(_priceMeta);
    }
    if (data.containsKey('discount_price')) {
      context.handle(
          _discountPriceMeta,
          discountPrice.isAcceptableOrUnknown(
              data['discount_price']!, _discountPriceMeta));
    }
    if (data.containsKey('vendor_i_d')) {
      context.handle(_vendorIDMeta,
          vendorID.isAcceptableOrUnknown(data['vendor_i_d']!, _vendorIDMeta));
    } else if (isInserting) {
      context.missing(_vendorIDMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(_quantityMeta,
          quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta));
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('extras_price')) {
      context.handle(
          _extras_priceMeta,
          extras_price.isAcceptableOrUnknown(
              data['extras_price']!, _extras_priceMeta));
    }
    if (data.containsKey('extras')) {
      context.handle(_extrasMeta,
          extras.isAcceptableOrUnknown(data['extras']!, _extrasMeta));
    }
    if (data.containsKey('variant_info')) {
      context.handle(
          _variantInfoMeta,
          variant_info.isAcceptableOrUnknown(
              data['variant_info']!, _variantInfoMeta));
    }
    if (data.containsKey('bundle_id')) {
      context.handle(_bundleIdMeta,
          bundleId.isAcceptableOrUnknown(data['bundle_id']!, _bundleIdMeta));
    }
    if (data.containsKey('bundle_name')) {
      context.handle(
          _bundleNameMeta,
          bundleName.isAcceptableOrUnknown(
              data['bundle_name']!, _bundleNameMeta));
    }
    if (data.containsKey('addon_promo_id')) {
      context.handle(
          _addonPromoIdMeta,
          addonPromoId.isAcceptableOrUnknown(
              data['addon_promo_id']!, _addonPromoIdMeta));
    }
    if (data.containsKey('addon_promo_name')) {
      context.handle(
          _addonPromoNameMeta,
          addonPromoName.isAcceptableOrUnknown(
              data['addon_promo_name']!, _addonPromoNameMeta));
    }
    if (data.containsKey('added_at')) {
      context.handle(_addedAtMeta,
          addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta));
    }
    if (data.containsKey('last_modified_at')) {
      context.handle(
          _lastModifiedAtMeta,
          lastModifiedAt.isAcceptableOrUnknown(
              data['last_modified_at']!, _lastModifiedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CartProduct map(Map<String, dynamic> data, {String? tablePrefix}) {
    return CartProduct.fromData(data, attachedDatabase,
        prefix: tablePrefix != null ? '$tablePrefix.' : null);
  }

  @override
  $CartProductsTable createAlias(String alias) {
    return $CartProductsTable(attachedDatabase, alias);
  }
}

abstract class _$CartDatabase extends GeneratedDatabase {
  _$CartDatabase(QueryExecutor e) : super(SqlTypeSystem.defaultInstance, e);
  late final $CartProductsTable cartProducts = $CartProductsTable(this);
  @override
  Iterable<TableInfo> get allTables => allSchemaEntities.whereType<TableInfo>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [cartProducts];
}
