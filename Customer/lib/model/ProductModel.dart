import 'package:foodie_customer/model/ItemAttributes.dart';
import 'package:foodie_customer/model/variant_info.dart';

class ProductModel {
  String categoryID;
  String brandID;
  String description;
  String id;
  String photo;
  List<dynamic> photos;
  String price;
  String name;
  String vendorID;
  String sectionId;
  int quantity;
  bool publish;
  int calories;
  int grams;
  int proteins;
  int fats;
  bool veg;
  bool nonveg;
  String? disPrice = "0";
  bool takeaway;
  List<dynamic> addOnsTitle = [];
  List<dynamic> addOnsPrice = [];
  String? addonName;
  String? addonPrice;
  ItemAttributes? itemAttributes;
  Map<String, dynamic>? reviewAttributes;
  Map<String, dynamic> specification = {};
  num reviewsCount;
  num reviewsSum;
  int? orderCount;
  VariantInfo? variantInfo;
  String? status;

  //List<AddAddonsDemo> lstAddOnsCustom=[];

  ProductModel({
    this.categoryID = '',
    this.brandID = '',
    this.description = '',
    this.id = '',
    this.photo = '',
    this.photos = const [],
    this.price = '',
    this.name = '',
    this.quantity = 0,
    this.vendorID = '',
    this.sectionId = '',
    this.calories = 0,
    this.grams = 0,
    this.proteins = 0,
    this.fats = 0,
    this.publish = true,
    this.veg = false,
    this.nonveg = false,
    this.addonName,
    this.addonPrice,
    this.disPrice,
    this.takeaway = false,
    this.reviewsCount = 0,
    this.reviewsSum = 0,
    this.orderCount,
    this.addOnsPrice = const [],
    this.addOnsTitle = const [],
    this.itemAttributes,
    this.variantInfo,
    this.specification = const {},
    this.reviewAttributes,
    this.status,
  });

  factory ProductModel.fromJson(Map<String, dynamic> parsedJson) {
    return ProductModel(
      categoryID: parsedJson['categoryID']?.toString() ?? '',
      brandID: parsedJson['brandID']?.toString() ?? '',
      description: parsedJson['description']?.toString() ?? '',
      id: parsedJson['id']?.toString() ?? '',
      photo: parsedJson['photo']?.toString() ?? '',
      photos: parsedJson['photos'] is List ? parsedJson['photos'] : [],
      price: parsedJson['price']?.toString() ?? '',
      quantity: (parsedJson['quantity'] is int)
          ? parsedJson['quantity']
          : (parsedJson['quantity'] is num
              ? parsedJson['quantity'].toInt()
              : 0),
      name: parsedJson['name']?.toString() ?? '',
      vendorID: parsedJson['vendorID']?.toString() ?? '',
      sectionId: parsedJson['section_id']?.toString() ?? '',
      publish: parsedJson['publish'] is bool
          ? parsedJson['publish']
          : (parsedJson['publish'] == true ||
                  parsedJson['publish'] == 'true')
              ? true
              : false,
      calories: (parsedJson['calories'] is int)
          ? parsedJson['calories']
          : (parsedJson['calories'] is num
              ? parsedJson['calories'].toInt()
              : 0),
      grams: (parsedJson['grams'] is int)
          ? parsedJson['grams']
          : (parsedJson['grams'] is num ? parsedJson['grams'].toInt() : 0),
      proteins: (parsedJson['proteins'] is int)
          ? parsedJson['proteins']
          : (parsedJson['proteins'] is num
              ? parsedJson['proteins'].toInt()
              : 0),
      fats: (parsedJson['fats'] is int)
          ? parsedJson['fats']
          : (parsedJson['fats'] is num ? parsedJson['fats'].toInt() : 0),
      nonveg: parsedJson['nonveg'] is bool ? parsedJson['nonveg'] : false,
      disPrice: parsedJson['disPrice']?.toString() ?? '0',
      specification: parsedJson['product_specification'] is Map
          ? Map<String, dynamic>.from(parsedJson['product_specification'])
          : {},
      takeaway: parsedJson['takeawayOption'] is bool
          ? parsedJson['takeawayOption']
          : false,
      addOnsPrice: parsedJson['addOnsPrice'] is List
          ? parsedJson['addOnsPrice']
          : [],
      addOnsTitle: parsedJson['addOnsTitle'] is List
          ? parsedJson['addOnsTitle']
          : [],
      reviewsCount: (parsedJson['reviewsCount'] is num)
          ? parsedJson['reviewsCount']
          : 0,
      reviewsSum: (parsedJson['reviewsSum'] is num)
          ? parsedJson['reviewsSum']
          : 0,
      orderCount: (parsedJson['orderCount'] is int)
          ? parsedJson['orderCount']
          : (parsedJson['orderCount'] is num
              ? parsedJson['orderCount'].toInt()
              : null),
      variantInfo: (parsedJson.containsKey('variant_info') &&
              parsedJson['variant_info'] != null)
          ? parsedJson['variant_info'].runtimeType.toString() ==
                  '_InternalLinkedHashMap<String, dynamic>'
              ? VariantInfo.fromJson(parsedJson['variant_info'])
              : null
          : null,
      reviewAttributes: parsedJson['reviewAttributes'] is Map
          ? Map<String, dynamic>.from(parsedJson['reviewAttributes'])
          : {},
      addonName: parsedJson["addon_name"]?.toString() ?? "",
      addonPrice: parsedJson["addon_price"]?.toString() ?? "",
      veg: parsedJson['veg'] is bool ? parsedJson['veg'] : false,
      itemAttributes: (parsedJson.containsKey('item_attribute') &&
              parsedJson['item_attribute'] != null)
          ? ItemAttributes.fromJson(parsedJson['item_attribute'])
          : null,
      status: parsedJson['status']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    photos.toList().removeWhere((element) => element == null);
    return {
      'categoryID': categoryID,
      'brandID': brandID,
      'description': description,
      'id': id,
      'photo': photo,
      'photos': photos,
      'price': price,
      'name': name,
      'quantity': quantity,
      'vendorID': vendorID,
      'section_id': sectionId,
      'publish': publish,
      'calories': calories,
      'grams': grams,
      'proteins': proteins,
      'fats': fats,
      'veg': veg,
      'nonveg': nonveg,
      'takeawayOption': takeaway,
      'disPrice': disPrice,
      "addOnsTitle": addOnsTitle,
      "addOnsPrice": addOnsPrice,
      "addon_name": addonName,
      "addon_price": addonPrice,
      'item_attribute':
          itemAttributes == null ? null : itemAttributes!.toJson(),
      'product_specification': specification,
      'reviewAttributes': reviewAttributes,
      'reviewsCount': reviewsCount,
      'reviewsSum': reviewsSum,
      'orderCount': orderCount,
      'status': status,
    };
  }
}

class ReviewsAttribute {
  num? reviewsCount;
  num? reviewsSum;

  ReviewsAttribute({
    this.reviewsCount,
    this.reviewsSum,
  });

  ReviewsAttribute.fromJson(Map<String, dynamic> json) {
    reviewsCount = json['reviewsCount'] ?? 0;
    reviewsSum = json['reviewsSum'] ?? 0;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['reviewsCount'] = reviewsCount;
    data['reviewsSum'] = reviewsSum;
    return data;
  }
}
