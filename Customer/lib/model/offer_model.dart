import 'package:cloud_firestore/cloud_firestore.dart';

class OfferModel {
  String? offerId;
  String? offerCode;
  String? descriptionOffer;
  String? discount;
  String? discountType;
  Timestamp? expireOfferDate;
  bool? isEnableOffer;
  String? imageOffer = "";
  String? restaurantId;
  
  // Additional fields for manual coupon feature
  double? minOrderAmount;
  int? usageLimit;
  int? usedCount;
  List<String>? eligibleUserIds;
  String? title;
  String? shortDescription;
  Timestamp? validFrom;
  Timestamp? validUntil;
  int? minItems; // Minimum number of items required
  Map<String, dynamic>? eligibilityRules; // User eligibility rules

  OfferModel({
    this.descriptionOffer,
    this.discount,
    this.discountType,
    this.expireOfferDate,
    this.imageOffer = "",
    this.isEnableOffer,
    this.offerCode,
    this.offerId,
    this.restaurantId,
    this.minOrderAmount,
    this.usageLimit,
    this.usedCount,
    this.eligibleUserIds,
    this.title,
    this.shortDescription,
    this.validFrom,
    this.validUntil,
    this.minItems,
    this.eligibilityRules,
  });

  factory OfferModel.fromJson(Map<String, dynamic> parsedJson) {
    List<String>? eligibleUserIdsList;
    if (parsedJson["eligibleUserIds"] != null) {
      eligibleUserIdsList = List<String>.from(parsedJson["eligibleUserIds"]);
    }
    
    // Handle image field - check imageUrl first (new format), then image, then photo
    String? imageValue = parsedJson["imageUrl"] ?? 
                         parsedJson["image"] ?? 
                         parsedJson["photo"] ?? 
                         "";
    
    // Handle discount field - check discountValue first (new format), then discount
    String? discountValue = parsedJson["discountValue"]?.toString() ?? 
                            parsedJson["discount"]?.toString();
    
    // Handle expiration date - check validTo first (new format), then expiresAt, then expireOfferDate
    Timestamp? expireDate = parsedJson["validTo"] ?? 
                            parsedJson["expiresAt"] ?? 
                            parsedJson["expireOfferDate"];
    
    // Handle usage limit - check globalUsageLimit first (new format), then usageLimit
    int? usageLimitValue = parsedJson["globalUsageLimit"] != null
        ? (parsedJson["globalUsageLimit"] is int
            ? parsedJson["globalUsageLimit"]
            : int.tryParse(parsedJson["globalUsageLimit"].toString()))
        : (parsedJson["usageLimit"] != null
            ? (parsedJson["usageLimit"] is int
                ? parsedJson["usageLimit"]
                : int.tryParse(parsedJson["usageLimit"].toString()))
            : null);
    
    // Handle restaurant ID - check both possible field names
    String? restaurantIdValue = parsedJson["restaurantId"] ?? 
                                 parsedJson["resturant_id"] ?? 
                                 "";
    
    // Handle ID - use document ID if id field is not present
    String? offerIdValue = parsedJson["id"] ?? "";
    
    return OfferModel(
        descriptionOffer: parsedJson["description"],
        discount: discountValue,
        discountType: parsedJson["discountType"],
        expireOfferDate: expireDate,
        imageOffer: imageValue,
        isEnableOffer: parsedJson["isEnabled"],
        offerCode: parsedJson["code"],
        offerId: offerIdValue,
        restaurantId: restaurantIdValue,
        minOrderAmount: parsedJson["minOrderAmount"] != null 
            ? (parsedJson["minOrderAmount"] is num 
                ? (parsedJson["minOrderAmount"] as num).toDouble() 
                : double.tryParse(parsedJson["minOrderAmount"].toString()))
            : null,
        usageLimit: usageLimitValue,
        usedCount: parsedJson["usedCount"] != null 
            ? (parsedJson["usedCount"] is int 
                ? parsedJson["usedCount"] 
                : int.tryParse(parsedJson["usedCount"].toString()))
            : null,
        eligibleUserIds: eligibleUserIdsList,
        title: parsedJson["title"],
        shortDescription: parsedJson["shortDescription"],
        validFrom: parsedJson["validFrom"],
        validUntil: parsedJson["validTo"] ?? parsedJson["validUntil"],
        minItems: parsedJson["minItems"] != null
            ? (parsedJson["minItems"] is int
                ? parsedJson["minItems"] as int
                : int.tryParse(parsedJson["minItems"].toString()))
            : null,
        eligibilityRules: parsedJson["eligibilityRules"] != null
            ? Map<String, dynamic>.from(parsedJson["eligibilityRules"])
            : null);
  }

  Map<String, dynamic> toJson() {
    return {
      "description": this.descriptionOffer,
      "discount": this.discount,
      "discountType": this.discountType,
      "expiresAt": this.expireOfferDate,
      "image": this.imageOffer,
      "isEnabled": this.isEnableOffer,
      "code": this.offerCode,
      "id": this.offerId,
      "resturant_id": this.restaurantId,
      "minOrderAmount": this.minOrderAmount,
      "usageLimit": this.usageLimit,
      "usedCount": this.usedCount,
      "eligibleUserIds": this.eligibleUserIds,
      "title": this.title,
      "shortDescription": this.shortDescription,
      "validFrom": this.validFrom,
      "validUntil": this.validUntil,
      "minItems": this.minItems,
      if (this.eligibilityRules != null) "eligibilityRules": this.eligibilityRules,
    };
  }
}
