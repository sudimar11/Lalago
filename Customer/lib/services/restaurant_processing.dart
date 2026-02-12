import 'package:intl/intl.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/ui/home/sections/restaurant_filter_card.dart';

/// Top-level function to filter and sort restaurants
/// Used with compute() to process off main thread
/// 
/// Input: Map with:
///   - 'restaurants': List<Map<String, dynamic>> (serialized VendorModel list)
///   - 'sortOption': String (SortOption enum name)
///   - 'filterRating4Plus': bool
///   - 'filterHalal': bool
/// 
/// Output: List<Map<String, dynamic>> (serialized filtered and sorted VendorModel list)
List<Map<String, dynamic>> filterAndSortRestaurants(Map<String, dynamic> input) {
  try {
    final List<Map<String, dynamic>> restaurantMaps = 
        List<Map<String, dynamic>>.from(input['restaurants'] as List);
    final String? sortOptionString = input['sortOption'] as String?;
    final bool filterRating4Plus = input['filterRating4Plus'] as bool? ?? false;
    final bool filterHalal = input['filterHalal'] as bool? ?? false;

    // Convert maps to VendorModel objects
    final List<VendorModel> restaurants = restaurantMaps
        .map((map) => VendorModel.fromJson(map))
        .toList();

    // Filter restaurants (but don't filter out closed restaurants - they'll be sorted to the end)
    List<VendorModel> filtered = restaurants.where((restaurant) {
      // REMOVED: Don't filter out closed restaurants
      // They will be sorted to the end by sortRestaurantsByOption

      // Filter by rating 4+
      if (filterRating4Plus) {
        final double rating = restaurant.reviewsCount != 0
            ? (restaurant.reviewsSum / restaurant.reviewsCount)
            : 0.0;
        if (rating < 4.0) {
          return false;
        }
      }

      // Filter by halal (check filters map)
      if (filterHalal) {
        // Assuming halal filter is in the filters map
        // Adjust based on actual filter structure
        final filters = restaurant.filters;
        if (filters.containsKey('Halal') && filters['Halal'] != 'Yes') {
          return false;
        }
      }

      return true;
    }).toList();

    // Sort restaurants
    final SortOption? sortOption = sortOptionString != null
        ? SortOption.values.firstWhere(
            (e) => e.toString().split('.').last == sortOptionString,
            orElse: () => SortOption.none,
          )
        : SortOption.none;

    final List<VendorModel> sorted = sortRestaurantsByOption(
      filtered,
      sortOption ?? SortOption.none,
    );

    // Convert back to maps
    return sorted.map((r) => r.toJson()).toList();
  } catch (e) {
    // Return empty list on error
    return [];
  }
}

/// Top-level function to check if a restaurant is open
/// Used with compute() to process off main thread
/// 
/// Input: Map<String, dynamic> (serialized VendorModel)
/// Output: bool
bool checkRestaurantOpen(Map<String, dynamic> vendorMap) {
  try {
    final VendorModel vendor = VendorModel.fromJson(vendorMap);
    
    final now = DateTime.now();
    final day = DateFormat('EEEE', 'en_US').format(now);
    final date = DateFormat('dd-MM-yyyy').format(now);

    bool isOpen = false;

    for (var workingHour in vendor.workingHours) {
      if (day == workingHour.day.toString()) {
        if (workingHour.timeslot != null && workingHour.timeslot!.isNotEmpty) {
          for (var timeSlot in workingHour.timeslot!) {
            final start = DateFormat("dd-MM-yyyy HH:mm")
                .parse(date + " " + timeSlot.from.toString());
            final end = DateFormat("dd-MM-yyyy HH:mm")
                .parse(date + " " + timeSlot.to.toString());

            if (isCurrentDateInRange(start, end)) {
              isOpen = true;
              break;
            }
          }
        }
        if (isOpen) break;
      }
    }

    return isOpen && vendor.reststatus;
  } catch (e) {
    return false;
  }
}

/// Helper function to check if current date is in range
bool isCurrentDateInRange(DateTime startDate, DateTime endDate) {
  final currentDate = DateTime.now();
  return currentDate.isAfter(startDate) && currentDate.isBefore(endDate);
}

/// Returns true if the restaurant is currently open (within working hours).
bool isRestaurantOpenFromModel(VendorModel vendor) {
  try {
    return checkRestaurantOpen(vendor.toJson());
  } catch (_) {
    return false;
  }
}

/// Returns formatted next opening time, or null if none found.
/// E.g. "Opens at 5:00 PM" (today) or "Opens Mon at 10:00 AM" (another day).
String? getNextOpeningTimeText(VendorModel vendor) {
  try {
    final next = _getNextOpeningDateTime(vendor);
    if (next == null) return null;
    final now = DateTime.now();
    final isToday = next.year == now.year &&
        next.month == now.month &&
        next.day == now.day;
    if (isToday) {
      return 'Opens at ${DateFormat('h:mm a').format(next)}';
    }
    return 'Opens ${DateFormat('EEE').format(next)} at '
        '${DateFormat('h:mm a').format(next)}';
  } catch (_) {
    return null;
  }
}

DateTime? _getNextOpeningDateTime(VendorModel vendor) {
  if (vendor.workingHours.isEmpty) return null;
  final now = DateTime.now();
  for (var i = 0; i < 8; i++) {
    final checkDate = now.add(Duration(days: i));
    final dayName = DateFormat('EEEE', 'en_US').format(checkDate);
    final dateStr = DateFormat('dd-MM-yyyy').format(checkDate);
    for (var wh in vendor.workingHours) {
      if (wh.day != dayName ||
          wh.timeslot == null ||
          wh.timeslot!.isEmpty) continue;
      for (var slot in wh.timeslot!) {
        if (slot.from == null || slot.from!.isEmpty) continue;
        final start = DateFormat('dd-MM-yyyy HH:mm')
            .parse('$dateStr ${slot.from}');
        if (start.isAfter(now)) return start;
      }
    }
  }
  return null;
}

/// Top-level function to sort restaurants by option
/// Used with compute() to process off main thread
/// 
/// Input: Map with:
///   - 'restaurants': List<Map<String, dynamic>> (serialized VendorModel list)
///   - 'sortOption': String (SortOption enum name)
/// 
/// Output: List<Map<String, dynamic>> (serialized sorted VendorModel list)
List<Map<String, dynamic>> sortRestaurantsByOptionWrapper(Map<String, dynamic> input) {
  try {
    final List<Map<String, dynamic>> restaurantMaps = 
        List<Map<String, dynamic>>.from(input['restaurants'] as List);
    final String? sortOptionString = input['sortOption'] as String?;

    // Convert maps to VendorModel objects
    final List<VendorModel> restaurants = restaurantMaps
        .map((map) => VendorModel.fromJson(map))
        .toList();

    final SortOption? sortOption = sortOptionString != null
        ? SortOption.values.firstWhere(
            (e) => e.toString().split('.').last == sortOptionString,
            orElse: () => SortOption.none,
          )
        : SortOption.none;

    final List<VendorModel> sorted = sortRestaurantsByOption(
      restaurants,
      sortOption ?? SortOption.none,
    );

    // Convert back to maps
    return sorted.map((r) => r.toJson()).toList();
  } catch (e) {
    // Return original list on error
    return input['restaurants'] as List<Map<String, dynamic>>;
  }
}

/// Sort restaurants based on selected sort option
List<VendorModel> sortRestaurantsByOption(
  List<VendorModel> restaurants,
  SortOption sortOption,
) {
  // Separate open and closed restaurants
  List<VendorModel> openRestaurants = [];
  List<VendorModel> closedRestaurants = [];

  for (var restaurant in restaurants) {
    if (checkRestaurantOpen(restaurant.toJson())) {
      openRestaurants.add(restaurant);
    } else {
      closedRestaurants.add(restaurant);
    }
  }

  // Sort each group by existing sort option (if rating or distance is selected)
  if (sortOption == SortOption.rating) {
    openRestaurants.sort((a, b) {
      final double ratingA =
          a.reviewsCount != 0 ? (a.reviewsSum / a.reviewsCount) : 0;
      final double ratingB =
          b.reviewsCount != 0 ? (b.reviewsSum / b.reviewsCount) : 0;
      final int ratingComparison = ratingB.compareTo(ratingA);
      if (ratingComparison == 0) {
        return b.reviewsCount.compareTo(a.reviewsCount);
      }
      return ratingComparison;
    });
    closedRestaurants.sort((a, b) {
      final double ratingA =
          a.reviewsCount != 0 ? (a.reviewsSum / a.reviewsCount) : 0;
      final double ratingB =
          b.reviewsCount != 0 ? (b.reviewsSum / b.reviewsCount) : 0;
      final int ratingComparison = ratingB.compareTo(ratingA);
      if (ratingComparison == 0) {
        return b.reviewsCount.compareTo(a.reviewsCount);
      }
      return ratingComparison;
    });
  } else if (sortOption == SortOption.distance) {
    // Note: Distance sorting would require location data, keeping original order for now
    // If distance data is available, it should be sorted here
  }

  // Apply sort based on selected option
  if (sortOption == SortOption.open) {
    // Open restaurants first, then closed
    return [...openRestaurants, ...closedRestaurants];
  } else if (sortOption == SortOption.closed) {
    // Closed restaurants first, then open
    return [...closedRestaurants, ...openRestaurants];
  } else {
    // Default: open first, then closed (for distance, rating, or none)
    return [...openRestaurants, ...closedRestaurants];
  }
}

/// Top-level function for HomeScreen restaurant filtering and sorting
/// Filters open restaurants and sorts by rating
/// 
/// Input: List<Map<String, dynamic>> (serialized VendorModel list)
/// Output: List<Map<String, dynamic>> (serialized filtered and sorted VendorModel list)
List<Map<String, dynamic>> filterAndSortRestaurantsForHome(List<Map<String, dynamic>> restaurantMaps) {
  try {
    // Convert maps to VendorModel objects
    final List<VendorModel> restaurants = restaurantMaps
        .map((map) => VendorModel.fromJson(map))
        .toList();

    // Filter valid restaurants (open restaurants)
    final List<VendorModel> validRestaurants = restaurants
        .where((vendor) => checkRestaurantOpen(vendor.toJson()))
        .toList();

    // Sort by rating (highest rating first)
    validRestaurants.sort((a, b) {
      // Safely convert to appropriate types
      final double reviewsSumA = a.reviewsSum.toDouble();
      final double reviewsSumB = b.reviewsSum.toDouble();
      final num reviewsCountA = a.reviewsCount;
      final num reviewsCountB = b.reviewsCount;

      // Calculate ratings
      final double ratingA =
          reviewsCountA != 0 ? (reviewsSumA / reviewsCountA) : 0.0;
      final double ratingB =
          reviewsCountB != 0 ? (reviewsSumB / reviewsCountB) : 0.0;

      // Sort by rating (descending)
      final int ratingComparison = ratingB.compareTo(ratingA);

      // If equal, sort by review count
      if (ratingComparison == 0) {
        return reviewsCountB.compareTo(reviewsCountA);
      }

      return ratingComparison;
    });

    // Convert back to maps
    return validRestaurants.map((r) => r.toJson()).toList();
  } catch (e) {
    // Return empty list on error
    return [];
  }
}

