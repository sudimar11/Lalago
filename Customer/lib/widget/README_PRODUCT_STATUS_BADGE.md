# ProductStatusBadge Widget

## Overview

The `ProductStatusBadge` widget displays product images with status badges. When a product's status is "Order Rejected", it shows a grid of 30 recommended similar products instead of the normal status badges.

## Features

### Normal Status Display

- Product image with shadow and rounded corners
- "TOP SELLING" badge (green gradient) - always shown
- "SALE" badge (red gradient) - shown when product has discount

### Order Rejected Status

- Replaces entire Stack widget with recommendation grid
- Shows "Try These Instead" header with refresh icon
- 2x15 grid layout (2 columns, 15 rows) of recommended products
- Smart recommendation algorithm based on:
  1. Same category (highest priority)
  2. Same vendor
  3. Similar price range (±20%)
  4. Popular products (rating ≥ 4.0)
  5. Random products to fill remaining slots

## Usage

```dart
ProductStatusBadge(
  product: product,
  allProducts: allProducts,
  width: 80,
  height: 80,
)
```

## Parameters

- `product` (required): The ProductModel to display
- `allProducts` (required): List of all products for recommendations
- `width` (optional): Widget width, defaults to 80
- `height` (optional): Widget height, defaults to 80

## ProductModel Status Field

The ProductModel now includes a `status` field:

```dart
ProductModel(
  // ... other fields
  status: 'Order Rejected', // or any other status
)
```

## Testing

Use the `TestHelpers` class to create test products:

```dart
// Create a rejected order product
ProductModel rejectedProduct = TestHelpers.createRejectedOrderProduct();

// Create test products for recommendations
List<ProductModel> testProducts = TestHelpers.createTestProducts();
```

## Algorithm Details

The recommendation algorithm prioritizes products in this order:

1. **Same Category**: Products with matching `categoryID`
2. **Same Vendor**: Products from the same `vendorID`
3. **Similar Price**: Products within ±20% price range
4. **Popular Products**: Products with rating ≥ 4.0
5. **Random Fill**: Random products to reach 30 items

This ensures relevant recommendations while providing variety.
