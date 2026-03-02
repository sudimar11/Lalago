import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/ui/productDetailsScreen/ProductDetailsScreen.dart';
import 'package:moor_flutter/moor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'localDatabase.g.dart';

class CartProducts extends Table {
  TextColumn get id => text()();

  TextColumn get category_id => text().nullable()();

  TextColumn get name => text().withLength(max: 50)();

  TextColumn get photo => text()();

  TextColumn get price => text()();

  TextColumn get discountPrice => text().nullable()();

  TextColumn get vendorID => text()();

  IntColumn get quantity => integer()();

  // ignore: non_constant_identifier_names
  TextColumn get extras_price => text().nullable()();

  TextColumn get extras => text().nullable()();

  TextColumn get variant_info => text().nullable()();

  TextColumn get bundleId => text().nullable()();

  TextColumn get bundleName => text().nullable()();

  TextColumn get addonPromoId => text().nullable()();

  TextColumn get addonPromoName => text().nullable()();

  DateTimeColumn get addedAt =>
      dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get lastModifiedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@UseMoor(tables: [CartProducts])
class CartDatabase extends _$CartDatabase {
  CartDatabase()
      : super(FlutterQueryExecutor.inDatabaseFolder(
            path: 'db.sqlite', logStatements: true));

  addProduct(ProductModel model, CartDatabase cartDatabase,
      bool isIncerementQuantity) async {
    var joinTitleString = "";
    String mainPrice = "";
    List<AddAddonsDemo> lstAddOns = [];
    List<String> lstAddOnsTemp = [];
    double extrasPrice = 0.0;

    SharedPreferences sp = await SharedPreferences.getInstance();
    String addOns =
        sp.getString("musics_key") != null ? sp.getString('musics_key')! : "";

    bool isAddSame = false;

    if (!isAddSame) {
      if (model.disPrice != null &&
          model.disPrice!.isNotEmpty &&
          double.parse(model.disPrice!) != 0) {
        mainPrice = model.disPrice!;
      } else {
        mainPrice = model.price;
      }
    }

    if (addOns.isNotEmpty) {
      lstAddOns = AddAddonsDemo.decode(addOns);
      for (int a = 0; a < lstAddOns.length; a++) {
        AddAddonsDemo newAddonsObject = lstAddOns[a];
        if (newAddonsObject.categoryID == model.id) {
          if (newAddonsObject.isCheck == true) {
            lstAddOnsTemp.add(newAddonsObject.name!);
            extrasPrice += (double.parse(newAddonsObject.price!));
          }
        }
      }

      joinTitleString = lstAddOnsTemp.isEmpty ? "" : lstAddOnsTemp.join(",");
    }

    allCartProducts.then((products) async {
      final bool _productIsInList = products.any((product) =>
          product.id ==
          (model.id +
              "~" +
              (model.variantInfo != null
                  ? model.variantInfo!.variantId.toString()
                  : "")));
      if (_productIsInList) {
        CartProduct element = products.firstWhere((product) =>
            product.id ==
            (model.id +
                "~" +
                (model.variantInfo != null
                    ? model.variantInfo!.variantId.toString()
                    : "")));
        final now = DateTime.now();
        await cartDatabase.updateProduct(CartProduct(
            id: element.id,
            category_id: element.category_id,
            name: element.name,
            photo: element.photo,
            price: element.price,
            vendorID: element.vendorID,
            quantity:
                isIncerementQuantity ? element.quantity + 1 : element.quantity,
            extras_price: extrasPrice.toString(),
            extras: joinTitleString,
            discountPrice: element.discountPrice ?? "",
            bundleId: element.bundleId,
            bundleName: element.bundleName,
            addonPromoId: element.addonPromoId,
            addonPromoName: element.addonPromoName,
            addedAt: element.addedAt,
            lastModifiedAt: now,
            variant_info: element.variant_info));
      } else {
        final now = DateTime.now();
        CartProduct entity = CartProduct(
            id: model.id +
                "~" +
                (model.variantInfo != null
                    ? model.variantInfo!.variantId.toString()
                    : ""),
            category_id: model.categoryID,
            name: model.name,
            photo: model.photo,
            price: mainPrice,
            discountPrice: model.disPrice,
            vendorID: model.vendorID,
            quantity: isIncerementQuantity ? 1 : 0,
            extras_price: extrasPrice.toString(),
            extras: joinTitleString,
            variant_info: model.variantInfo,
            addedAt: now,
            lastModifiedAt: now);
        if (products.where((element) => element.id == model.id).isEmpty) {
          into(cartProducts).insert(entity);
        } else {
          updateProduct(entity);
        }
      }
    });
  }

  Future<void> reAddProduct(CartProduct cartProduct) async {
    try {
      // Check if product already exists in cart
      final products = await allCartProducts;
      final productExists =
          products.any((product) => product.id == cartProduct.id);

      if (productExists) {
        // Update existing product (merge quantities)
        final existingProduct =
            products.firstWhere((product) => product.id == cartProduct.id);
        final categoryId =
            cartProduct.category_id ?? cartProduct.id.split('~').first;
        final now = DateTime.now();
        await updateProduct(CartProduct(
          id: cartProduct.id,
          category_id: categoryId.isEmpty ? cartProduct.id : categoryId,
          name: cartProduct.name,
          photo: cartProduct.photo,
          price: cartProduct.price,
          discountPrice: cartProduct.discountPrice ?? "",
          vendorID: cartProduct.vendorID,
          quantity: existingProduct.quantity + cartProduct.quantity,
          extras_price: cartProduct.extras_price,
          extras: cartProduct.extras,
          variant_info: cartProduct.variant_info,
          addonPromoId: cartProduct.addonPromoId,
          addonPromoName: cartProduct.addonPromoName,
          addedAt: existingProduct.addedAt,
          lastModifiedAt: now,
        ));
      } else {
        // Ensure category_id is set before inserting
        final categoryId =
            cartProduct.category_id ?? cartProduct.id.split('~').first;
        final now = DateTime.now();
        final productToInsert = CartProduct(
          id: cartProduct.id,
          category_id: categoryId.isEmpty ? cartProduct.id : categoryId,
          name: cartProduct.name,
          photo: cartProduct.photo,
          price: cartProduct.price,
          discountPrice: cartProduct.discountPrice ?? "",
          vendorID: cartProduct.vendorID,
          quantity: cartProduct.quantity,
          extras_price: cartProduct.extras_price,
          extras: cartProduct.extras,
          variant_info: cartProduct.variant_info,
          addonPromoId: cartProduct.addonPromoId,
          addonPromoName: cartProduct.addonPromoName,
          addedAt: now,
          lastModifiedAt: now,
        );
        await into(cartProducts).insert(productToInsert);
      }
    } catch (e, stackTrace) {
      debugPrint("Error in reAddProduct: $e");
      debugPrint("StackTrace: $stackTrace");
      // If insert fails, try update as fallback
      try {
        final categoryId =
            cartProduct.category_id ?? cartProduct.id.split('~').first;
        final now = DateTime.now();
        await updateProduct(CartProduct(
          id: cartProduct.id,
          category_id: categoryId.isEmpty ? cartProduct.id : categoryId,
          name: cartProduct.name,
          photo: cartProduct.photo,
          price: cartProduct.price,
          discountPrice: cartProduct.discountPrice ?? "",
          vendorID: cartProduct.vendorID,
          quantity: cartProduct.quantity,
          extras_price: cartProduct.extras_price,
          extras: cartProduct.extras,
          variant_info: cartProduct.variant_info,
          addonPromoId: cartProduct.addonPromoId,
          addonPromoName: cartProduct.addonPromoName,
          addedAt: cartProduct.addedAt,
          lastModifiedAt: now,
        ));
      } catch (updateError) {
        debugPrint("Update also failed: $updateError");
        rethrow;
      }
    }
  }

  removeProduct(String productID) =>
      (delete(cartProducts)..where((product) => product.id.equals(productID)))
          .go();

  deleteAllProducts() => (delete(cartProducts)).go();

  updateProduct(CartProduct entity) =>
      (update(cartProducts)..where((product) => product.id.equals(entity.id)))
          .write(entity);

  Future<void> touchLastModified(String productId) async {
    await (update(cartProducts)..where((t) => t.id.equals(productId)))
        .write(CartProductsCompanion(lastModifiedAt: Value(DateTime.now())));
  }

  /// Adds all items of a bundle as separate cart lines with the same bundleId/bundleName.
  /// [items] each has productId, productName, photo, quantity. [bundlePrice] is split
  /// so that the sum of line totals equals bundlePrice.
  Future<void> addBundleToCart({
    required String bundleId,
    required String bundleName,
    required String vendorID,
    required double bundlePrice,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) return;
    int totalQty = 0;
    for (final item in items) {
      totalQty += (item['quantity'] is int)
          ? item['quantity'] as int
          : (int.tryParse(item['quantity']?.toString() ?? '1') ?? 1);
    }
    if (totalQty <= 0) return;
    final unitPrice = bundlePrice / totalQty;
    final categoryId = items.first['category_id']?.toString() ?? '';

    for (final item in items) {
      final productId = (item['productId'] ?? item['id'] ?? '').toString();
      if (productId.isEmpty) continue;
      final productName =
          (item['productName'] ?? item['name'] ?? 'Item').toString();
      final photo = (item['photo'] ?? item['imageUrl'] ?? '').toString();
      final qty = (item['quantity'] is int)
          ? item['quantity'] as int
          : (int.tryParse(item['quantity']?.toString() ?? '1') ?? 1);
      if (qty <= 0) continue;
      final priceStr = unitPrice.toStringAsFixed(2);
      // id format productId~bundle_bundleId so order toJson (id.split('~').first) sends productId
      final cartLineId = '${productId}~bundle_$bundleId';

      final now = DateTime.now();
      final cp = CartProduct(
        id: cartLineId,
        category_id: categoryId,
        name: productName,
        photo: photo,
        price: priceStr,
        discountPrice: '',
        vendorID: vendorID,
        quantity: qty,
        extras_price: null,
        extras: null,
        variant_info: null,
        bundleId: bundleId,
        bundleName: bundleName,
        addedAt: now,
        lastModifiedAt: now,
      );
      final existing = await allCartProducts;
      final match = existing
          .where((p) => p.id == cartLineId && p.bundleId == bundleId)
          .toList();
      if (match.isNotEmpty) {
        final e = match.first;
        await updateProduct(CartProduct(
          id: e.id,
          category_id: e.category_id ?? categoryId,
          name: e.name,
          photo: e.photo,
          price: e.price,
          discountPrice: e.discountPrice,
          vendorID: e.vendorID,
          quantity: e.quantity + qty,
          extras_price: e.extras_price,
          extras: e.extras,
          variant_info: e.variant_info,
          bundleId: e.bundleId,
          bundleName: e.bundleName,
          addedAt: e.addedAt,
          lastModifiedAt: now,
        ));
      } else {
        await into(cartProducts).insert(cp);
      }
    }
  }

  /// Adds a single add-on product to cart at addon price with promo tracking.
  /// Cart line id: productId~addon_addonPromoId so same addon can be merged.
  Future<void> addAddonToCart({
    required String addonPromoId,
    required String addonPromoName,
    required String productId,
    required String productName,
    required String photo,
    required double addonPrice,
    required String vendorID,
    int quantity = 1,
  }) async {
    if (quantity < 1) return;
    final categoryId = productId;
    final priceStr = addonPrice.toStringAsFixed(2);
    final cartLineId = '${productId}~addon_$addonPromoId';

    final now = DateTime.now();
    final cp = CartProduct(
      id: cartLineId,
      category_id: categoryId,
      name: productName,
      photo: photo,
      price: priceStr,
      discountPrice: '',
      vendorID: vendorID,
      quantity: quantity,
      extras_price: null,
      extras: null,
      variant_info: null,
      bundleId: null,
      bundleName: null,
      addonPromoId: addonPromoId,
      addonPromoName: addonPromoName,
      addedAt: now,
      lastModifiedAt: now,
    );
    final existing = await allCartProducts;
    final match = existing
        .where((p) => p.id == cartLineId && p.addonPromoId == addonPromoId)
        .toList();
    if (match.isNotEmpty) {
      final e = match.first;
      await updateProduct(CartProduct(
        id: e.id,
        category_id: e.category_id ?? categoryId,
        name: e.name,
        photo: e.photo,
        price: e.price,
        discountPrice: e.discountPrice,
        vendorID: e.vendorID,
        quantity: e.quantity + quantity,
        extras_price: e.extras_price,
        extras: e.extras,
        variant_info: e.variant_info,
        bundleId: e.bundleId,
        bundleName: e.bundleName,
        addonPromoId: e.addonPromoId,
        addonPromoName: e.addonPromoName,
        addedAt: e.addedAt,
        lastModifiedAt: now,
      ));
    } else {
      await into(cartProducts).insert(cp);
    }
  }

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            await migrator.addColumn(
                cartProducts, cartProducts.bundleId);
            await migrator.addColumn(
                cartProducts, cartProducts.bundleName);
          }
          if (from < 3) {
            await migrator.addColumn(
                cartProducts, cartProducts.addonPromoId);
            await migrator.addColumn(
                cartProducts, cartProducts.addonPromoName);
          }
          if (from < 4) {
            await migrator.addColumn(cartProducts, cartProducts.addedAt);
            await migrator.addColumn(
                cartProducts, cartProducts.lastModifiedAt);
          }
          if (from < 5) {
            try {
              await migrator.addColumn(
                  cartProducts, cartProducts.category_id);
            } catch (_) {}
            try {
              await migrator.addColumn(
                  cartProducts, cartProducts.variant_info);
            } catch (_) {}
          }
        },
      );

  Future<List<CartProduct>> get allCartProducts => select(cartProducts).get();

  Stream<List<CartProduct>> get watchProducts => select(cartProducts).watch();
}
