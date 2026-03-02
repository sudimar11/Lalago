import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/services/click_tracking_service.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/vendorProductsScreen/newVendorProductsScreen.dart';

class PopularsCard extends StatelessWidget {
  final VendorModel vendorModel;

  const PopularsCard({
    Key? key,
    required this.vendorModel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: GestureDetector(
        onTap: () {
          ClickTrackingService.logClick(
            userId: MyAppState.currentUser?.userID ?? 'guest',
            restaurantId: vendorModel.id,
            source: 'popular_today',
          );
          push(context, NewVendorProductsScreen(vendorModel: vendorModel));
        },
        child: Container(
          width: MediaQuery.of(context).size.width * 0.75,
          decoration: BoxDecoration(
            color: isDarkMode(context) ? const Color(0xFF2C2C2C) : Colors.white,
            border: Border.all(
              color: isDarkMode(context)
                  ? Colors.grey.shade700
                  : Colors.grey.shade300,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Image Container with overlay
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      child: CachedNetworkImage(
                        imageUrl: getImageVAlidUrl(vendorModel.photo),
                        width: double.infinity,
                        height: double.infinity,
                        memCacheWidth: 280,
                        memCacheHeight: 280,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(24),
                              topRight: Radius.circular(24),
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(COLOR_PRIMARY).withOpacity(0.1),
                                Color(COLOR_PRIMARY).withOpacity(0.05),
                              ],
                            ),
                          ),
                          child: Center(
                            child: CircularProgressIndicator.adaptive(
                              valueColor:
                                  AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(24),
                              topRight: Radius.circular(24),
                            ),
                            color: Colors.grey.shade200,
                          ),
                          child: Icon(
                            Icons.restaurant,
                            size: 50,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ),
                    ),
                    // Gradient overlay for better text readability
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(24),
                            topRight: Radius.circular(24),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.3),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Rating badge
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star,
                              size: 16,
                              color: Color(COLOR_PRIMARY),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              vendorModel.reviewsCount != 0
                                  ? '${(vendorModel.reviewsSum / vendorModel.reviewsCount).toStringAsFixed(1)}'
                                  : '0.0',
                              style: TextStyle(
                                fontFamily: "Poppinsm",
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDarkMode(context)
                                    ? Colors.black
                                    : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // "POPULAR" badge
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.orange.shade400,
                              Colors.orange.shade600,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orange.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.trending_up,
                              size: 12,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'POPULAR',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Content section
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Restaurant name
                    Text(
                      vendorModel.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: "Poppinsm",
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                        color:
                            isDarkMode(context) ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Location row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Color(COLOR_PRIMARY).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.location_on,
                            size: 16,
                            color: Color(COLOR_PRIMARY),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            vendorModel.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: "Poppinsm",
                              fontSize: 14,
                              color: isDarkMode(context)
                                  ? Colors.white70
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Bottom row with reviews and popularity indicator
                    Row(
                      children: [
                        // Reviews count
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDarkMode(context)
                                ? Colors.white.withOpacity(0.1)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${vendorModel.reviewsCount} reviews',
                            style: TextStyle(
                              fontFamily: "Poppinsm",
                              fontSize: 12,
                              color: isDarkMode(context)
                                  ? Colors.white70
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Popularity indicator
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.local_fire_department,
                                size: 14,
                                color: Colors.orange.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Trending',
                                style: TextStyle(
                                  fontFamily: "Poppinsm",
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
