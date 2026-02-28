# Memory Profiling Guide & Codebase Findings

This document guides you through memory profiling to fix the OutOfMemoryError on the home screen, plus findings from a static code analysis.

---

## Part 1: Profiling Steps

### 1. Set Up Memory Profiling

```bash
cd Customer
flutter run --profile
```

- Profile mode enables Observatory and disables debug asserts for realistic performance
- Note the DevTools URL in the terminal (e.g. `http://127.0.0.1:9100`)
- Open it in a browser and go to the **Memory** tab
- Familiarize yourself with: memory graph, heap snapshots, allocation tracking

### 2. Reproduce the Crash While Profiling

- Start recording allocations in DevTools Memory tab
- Scroll through the home screen quickly, especially:
  - Category sections (Meals, etc.) with many restaurant cards
  - "View All" for categories
  - New arrival, popular, nearby sections
- Continue until memory rises and GC warnings appear, or the app crashes
- Record what happens just before the crash (which section, how far scrolled)

### 3. Capture Heap Snapshots

| Snapshot | When to Take |
|----------|--------------|
| **Baseline** | Before scrolling |
| **After scroll** | After scrolling through several categories |
| **After navigate** | After leaving home (e.g. profile) and returning |

In DevTools: **Diff** the snapshots and look for:

- Large objects: `ui.Image`, `Bitmap`, `ImageInfo`
- High instance counts: `RestaurantCard`, `_CategoryRestaurantCard`, `CachedNetworkImage`
- Objects that persist after navigating away (potential leaks)

### 4. Inspect Image Loading

See **Part 2: Codebase Findings** below for locations of `Image.network` and missing `memCacheWidth`/`memCacheHeight`.

### 5. Analyze Firestore Query Patterns

See **Part 2** for query analysis. Use Firestore Console to inspect document sizes (avoid large base64 images or big arrays).

### 6. Audit Lifecycle Management

See **Part 2** for StreamSubscription and dispose audit.

### 7. Monitor Garbage Collection

```bash
flutter run --verbose
```

Watch for `Alloc concurrent mark compact GC` or similar. After fixes, you should see fewer blocking GC events.

### 8. Check Custom Caches

See **Part 2** for cache usage.

### 9. Test on Low-Memory Devices

Run on a physical device with 2–3 GB RAM to surface memory issues sooner.

### 10. Document Your Findings

Use the template below after profiling:

---

**Findings Template** (fill in after profiling)

| Item | Value |
|------|-------|
| Top 5 largest object types in heap | |
| Widgets remaining after navigate away | |
| Firestore queries returning large datasets | |
| Memory increase per scroll (MB) | |
| Error messages / stack traces | |

---

## Part 2: Codebase Findings (Static Analysis)

### A. Image Loading

#### `Image.network` (no cache, no memory limits)

These load full-size images in memory and do not use `memCacheWidth`/`memCacheHeight`:

| File | Line | Context |
|------|------|---------|
| `home_restaurants_section.dart` | 144, 150 | Restaurant cards – **main culprit** (each category section) |
| `sections/restaurant_card.dart` | 130 | Error fallback (inside CachedNetworkImage) |
| `sections/home_popular_today_section.dart` | 200 | Popular today |
| `sections/home_nearby_foods_section.dart` | 194 | Nearby foods |
| `sections/home_categories_section.dart` | 156 | Category icons (error fallback) |
| `view_all_category_product_screen.dart` | 143 | View-all category list |
| `view_all_restaurant.dart` | 161 | View all restaurants |
| `view_all_popular_restaurant_screen.dart` | 147 | View all popular |
| `view_all_new_arrival_restaurant_screen.dart` | 143 | View all new arrivals |
| `view_all_popular_food_near_by_screen.dart` | 174 | View all popular food |
| `food_varieties.dart` | 281 | Food varieties |
| `favourite_restaurant.dart` | 240, 395 | Favourites |
| `favourite_item.dart` | 117 | Favourite item |
| `searchScreen/SearchScreen.dart` | 1003, 1145 | Search vendor/product images |

#### CachedNetworkImage without memCacheWidth/Height

Several `CachedNetworkImage` usages do not limit memory:

| File | Notes |
|------|-------|
| `home_restaurants_section.dart` | Uses `Image.network` for main image (not CachedNetworkImage) |
| `category_restaurants_section.dart` | Uses CachedNetworkImage but **no memCacheWidth/Height** |
| `restaurant_card.dart` | Main image has CachedNetworkImage but **no memCacheWidth/Height** |

#### Helper with high memory limits

[`helper.dart`](Customer/lib/services/helper.dart) lines 219–222, 263–265: `displayImage` and `displayCircleImage` use `memCacheWidth/Height: 1000` – consider 250–300 for list/card usage.

### B. Firestore Query Patterns

#### `getCategoryRestaurants` – loads all at once

- **File:** [`FirebaseHelper.dart`](Customer/lib/services/FirebaseHelper.dart) ~1938
- **Behavior:** GeoFire query returns all vendors in radius for a category (no limit)
- **Used by:** `home_restaurants_section.dart`, `category_restaurants_section.dart`, `view_all_category_product_screen.dart`
- **Problem:** With many categories (e.g. 12), you run 12 concurrent streams, each loading all restaurants in that category
- **Stream leak:** `stream.listen(...)` on the geo stream is never cancelled; the subscription is not stored

#### `getVendorsForNewArrival` – same pattern

- **File:** [`FirebaseHelper.dart`](Customer/lib/services/FirebaseHelper.dart) ~1996
- **Behavior:** Loads all vendors in radius, sorted by distance
- **Stream leak:** `stream.listen(...)` is never cancelled

#### Pagination exists but is not used for categories

- **File:** [`FirebaseHelper.dart`](Customer/lib/services/FirebaseHelper.dart) ~5192
- **Method:** `getRestaurantsPaginated` with `startAfterDocument`, `limit`
- **Used by:** `lazy_loading_widget.dart` only
- **Gap:** Category sections and view-all screens do **not** use pagination

### C. Lifecycle / StreamSubscription

#### Subscriptions cancelled in dispose

| File | Subscriptions |
|------|---------------|
| `HomeScreen.dart` | `orderAgainStreamSubscription`, `_completionDialogStreamSubscription`, `_restaurantStreamSubscription`, `_connectivitySubscription` – all cancelled in dispose |

#### Subscriptions not cancelled (leaks)

| File | Issue |
|------|-------|
| `view_all_category_product_screen.dart` | `getCategoryRestaurants(...).asBroadcastStream().listen(...)` – subscription never stored or cancelled |
| `view_all_popular_restaurant_screen.dart` | `vendorsFuture!.listen(...)` – subscription not cancelled |
| `view_all_popular_food_near_by_screen.dart` | `lstAllStore!.listen(...)` – subscription not cancelled |
| `view_all_restaurant.dart` | `stream.listen(...)` – subscription not cancelled |
| `FirebaseHelper.dart` | `getCategoryRestaurants` and `getVendorsForNewArrival` create `stream.listen(...)` internally; subscriptions are never cancelled when StreamBuilder is disposed |

### D. Custom Caches

- `SearchScreen` – `_searchCache` map, cleared in dispose
- `flutter_cache_manager` – default cache used by CachedNetworkImage; consider `CacheManager` with `maxNrOfCacheObjects` if needed

---

## Part 3: Recommended Fixes (Priority Order)

1. **Replace `Image.network` in `home_restaurants_section.dart`**  
   Use `CachedNetworkImage` with `memCacheWidth` and `memCacheHeight` (e.g. 250–300).

2. **Add `memCacheWidth`/`memCacheHeight` (250–300)** to:
   - `category_restaurants_section.dart` CachedNetworkImage
   - `restaurant_card.dart` CachedNetworkImage

3. **Fix `ViewAllCategoryProductScreen` stream leak**  
   Store the `StreamSubscription` from `getCategoryRestaurants(...).listen(...)` and cancel it in `dispose`.

4. **Add pagination to category restaurant loading**  
   Extend Firestore/API to support `getCategoryRestaurantsPaginated` (or similar) and load in batches (e.g. 10 per category) instead of all at once.

5. **Fix remaining `Image.network` usages**  
   Replace with `CachedNetworkImage` and `memCacheWidth`/`memCacheHeight` in the other listed files.

6. **Lower helper.dart memory limits**  
   Reduce `displayImage` / `displayCircleImage` from 1000 to ~250–300 where used in lists.

7. **Review FirebaseHelper stream lifecycle**  
   Make `getCategoryRestaurants` and `getVendorsForNewArrival` cancellable (e.g. return a stream that cancels the geo subscription when the listener cancels).

---

## Part 4: Quick Reference – CachedNetworkImage with Memory Limits

```dart
CachedNetworkImage(
  imageUrl: getImageVAlidUrl(url),
  memCacheWidth: 280,   // 200–300 for cards
  memCacheHeight: 280,
  fit: BoxFit.cover,
  placeholder: (context, url) => /* ... */,
  errorWidget: (context, url, error) => CachedNetworkImage(
    imageUrl: AppGlobal.placeHolderImage!,
    memCacheWidth: 120,
    memCacheHeight: 120,
    fit: BoxFit.cover,
  ),
)
```

Use `Image.network` only as a last fallback, and prefer `CachedNetworkImage` with memory limits for all network images on the home and list screens.
