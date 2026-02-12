import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:foodie_customer/model/advertisement.dart';
import 'package:foodie_customer/services/advertisement_service.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/constants.dart';

class AdvertisementSlider extends StatefulWidget {
  const AdvertisementSlider({super.key});

  @override
  State<AdvertisementSlider> createState() => _AdvertisementSliderState();
}

class _AdvertisementSliderState extends State<AdvertisementSlider> {
  final CarouselSliderController _carouselController =
      CarouselSliderController();
  int _currentIndex = 0;
  final Set<String> _trackedImpressions = {};

  @override
  Widget build(BuildContext context) {
    log('=== AdvertisementSlider: Building widget ===');
    return StreamBuilder<List<Advertisement>>(
      stream: AdvertisementService.getActiveAdsStream(),
      builder: (context, snapshot) {
        log('StreamBuilder state: ${snapshot.connectionState}');

        if (snapshot.connectionState == ConnectionState.waiting) {
          log('Showing loading state');
          return _buildLoadingState();
        }

        if (snapshot.hasError) {
          log('❌ ERROR in stream: ${snapshot.error}');
          log('StackTrace: ${snapshot.stackTrace}');
          debugPrint('Error loading advertisements: ${snapshot.error}');
          return _buildFallbackBanner();
        }

        final ads = snapshot.data ?? [];
        log('Received ${ads.length} advertisements from stream');

        if (ads.isEmpty) {
          log('No ads to display - showing fallback banner');
          return _buildFallbackBanner();
        }

        log('Building carousel with ${ads.length} ads');
        for (int i = 0; i < ads.length; i++) {
          log('  Ad ${i + 1}: ${ads[i].title} (${ads[i].imageUrls.length} images)');
          if (ads[i].imageUrls.isNotEmpty) {
            log('    First image URL: ${ads[i].imageUrls.first}');
          }
        }

        return _buildCarousel(ads);
      },
    );
  }

  Widget _buildCarousel(List<Advertisement> ads) {
    // Track impression for first ad
    if (ads.isNotEmpty && !_trackedImpressions.contains(ads[0].id)) {
      _trackedImpressions.add(ads[0].id);
      AdvertisementService.incrementImpression(ads[0].id);
    }

    log('Building carousel with ${ads.length} ads in priority order');
    for (int i = 0; i < ads.length; i++) {
      log('  Position $i: ${ads[i].title} (Priority: ${ads[i].priority}, ID: ${ads[i].id})');
    }

    return Column(
      children: [
        CarouselSlider.builder(
          carouselController: _carouselController,
          itemCount: ads.length,
          itemBuilder: (context, index, realIndex) {
            if (index >= ads.length) {
              log('  ⚠️ Index out of bounds: $index (ads.length: ${ads.length})');
              return _buildFallbackBanner();
            }
            final ad = ads[index];
            log('  Building carousel item at index $index: ${ad.title} (Priority: ${ad.priority})');
            return _buildAdItem(ad, index);
          },
          options: CarouselOptions(
            height: 180,
            viewportFraction: 1.0,
            autoPlay: ads.length > 1,
            autoPlayInterval: const Duration(seconds: 4),
            autoPlayAnimationDuration: const Duration(milliseconds: 800),
            autoPlayCurve: Curves.fastOutSlowIn,
            enlargeCenterPage: false,
            onPageChanged: (index, reason) {
              log('  📍 Carousel page changed to index: $index (Reason: $reason)');
              if (index < ads.length) {
                log('  Showing ad: ${ads[index].title} (Priority: ${ads[index].priority})');
              }
              setState(() {
                _currentIndex = index;
              });
              // Track impression when ad becomes visible
              if (index < ads.length) {
                final adId = ads[index].id;
                if (!_trackedImpressions.contains(adId)) {
                  _trackedImpressions.add(adId);
                  AdvertisementService.incrementImpression(adId);
                  log('  ✅ Tracked impression for ad: ${ads[index].title}');
                }
              }
            },
          ),
        ),
        if (ads.length > 1) ...[
          const SizedBox(height: 8),
          _buildIndicators(ads.length),
        ],
      ],
    );
  }

  Widget _buildAdItem(Advertisement ad, int index) {
    final rawImageUrl = ad.imageUrls.isNotEmpty ? ad.imageUrls.first : '';
    log('Building ad item #$index: ${ad.title} (Priority: ${ad.priority})');
    log('  Raw Image URL: $rawImageUrl');
    log('  Image URLs count: ${ad.imageUrls.length}');

    // Use raw URL directly if it's a valid Firebase Storage URL
    // Otherwise validate it
    String imageUrl;
    if (rawImageUrl.isEmpty) {
      log('  ⚠️ No image URL found for ad "${ad.title}", showing fallback');
      return _buildFallbackBanner();
    } else if (rawImageUrl.startsWith('https://') ||
        rawImageUrl.startsWith('http://')) {
      // Use Firebase Storage URL directly
      imageUrl = rawImageUrl;
      log('  ✅ Using Firebase Storage URL directly');
    } else {
      // Validate other URLs
      imageUrl = getImageVAlidUrl(rawImageUrl);
      // If validation returned placeholder, it means URL is invalid
      if (imageUrl == placeholderImage) {
        log('  ⚠️ Invalid URL for ad "${ad.title}", validation returned placeholder');
        return _buildFallbackBanner();
      }
    }

    log('  Final Image URL: $imageUrl');
    log('  URL length: ${imageUrl.length}');

    return GestureDetector(
      onTap: () => _handleAdClick(ad),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 32,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            height: 180,
            httpHeaders: const {
              'User-Agent': 'LalaGO-Customer-App',
            },
            placeholder: (context, url) {
              log('  ⏳ Loading image for ad "${ad.title}": $url');
              return Container(
                width: double.infinity,
                height: 180,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.orange.shade400,
                      Colors.deepOrange.shade400,
                    ],
                  ),
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              );
            },
            errorWidget: (context, url, error) {
              log('  ❌ ERROR loading image for ad "${ad.title}"');
              log('  Error: $error');
              log('  Failed URL: $url');
              log('  Raw URL from ad: $rawImageUrl');
              log('  Final URL used: $imageUrl');
              // Still show the ad with fallback banner instead of hiding it
              return _buildFallbackBanner();
            },
            fadeInDuration: const Duration(milliseconds: 300),
            fadeOutDuration: const Duration(milliseconds: 100),
          ),
        ),
      ),
    );
  }

  Widget _buildIndicators(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        count,
        (index) => Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _currentIndex == index
                ? Color(COLOR_PRIMARY)
                : Colors.grey.withOpacity(0.4),
          ),
        ),
      ),
    );
  }

  Future<void> _handleAdClick(Advertisement ad) async {
    // Track click
    AdvertisementService.incrementClick(ad.id);

    // Navigate to restaurant if restaurantId is provided
    if (ad.restaurantId != null && ad.restaurantId!.isNotEmpty) {
      try {
        final vendorModel = await FireStoreUtils.getVendor(ad.restaurantId!);
        if (vendorModel != null && mounted) {
          push(
            context,
            NewVendorProductsScreen(vendorModel: vendorModel),
          );
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Restaurant not found'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('Error navigating to restaurant: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to open restaurant'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  Widget _buildLoadingState() {
    return Container(
      height: 180,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.orange.shade400,
            Colors.deepOrange.shade400,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      ),
    );
  }

  Widget _buildFallbackBanner() {
    return Container(
      height: 180,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.orange.shade400,
            Colors.deepOrange.shade400,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: GestureDetector(
        onTap: () {
          // Navigate to popular restaurants
          // You can customize this navigation as needed
        },
        child: Stack(
          children: [
            // Decorative circles
            Positioned(
              right: -20,
              top: -20,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              right: 20,
              bottom: -10,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Welcome to LalaGO!",
                          style: const TextStyle(
                            fontFamily: 'Poppinsb',
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Discover amazing restaurants and delicious food near you.",
                          style: TextStyle(
                            fontFamily: 'Poppinsm',
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                            height: 1.35,
                            color: Colors.white.withOpacity(0.95),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.restaurant_menu,
                        size: 40,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
