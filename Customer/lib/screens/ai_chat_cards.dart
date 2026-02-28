import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/ai_cart_service.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/dineInScreen/my_booking_screen.dart';
import 'package:foodie_customer/ui/orderDetailsScreen/OrderDetailsScreen.dart';
import 'package:foodie_customer/ui/productDetailsScreen/ProductDetailsScreen.dart';
import 'package:foodie_customer/ui/vendorProductsScreen/newVendorProductsScreen.dart';

/// Restaurant list card for AI chat.
class RestaurantListCard extends StatelessWidget {
  const RestaurantListCard({
    Key? key,
    required this.data,
  }) : super(key: key);

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final restaurants =
        (data['restaurants'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final message = (data['message'] ?? '') as String? ?? '';

    if (restaurants.isEmpty) {
      return _buildMessageCard(context, message);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: restaurants.length,
            itemBuilder: (ctx, i) {
              final r = restaurants[i];
              return _RestaurantCard(
                id: (r['id'] ?? '').toString(),
                name: (r['name'] ?? r['title'] ?? '').toString(),
                cuisine: (r['cuisine'] ?? r['categoryTitle'] ?? '').toString(),
                rating: (r['rating'] ?? 0) is num
                    ? (r['rating'] as num).toDouble()
                    : 0.0,
                distance: r['distance'] is num ? (r['distance'] as num) : null,
                imageUrl: (r['imageUrl'] ?? '').toString(),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMessageCard(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium,
        maxLines: 10,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _RestaurantCard extends StatefulWidget {
  const _RestaurantCard({
    required this.id,
    required this.name,
    required this.cuisine,
    required this.rating,
    this.distance,
    required this.imageUrl,
  });

  final String id;
  final String name;
  final String cuisine;
  final double rating;
  final num? distance;
  final String imageUrl;

  @override
  State<_RestaurantCard> createState() => _RestaurantCardState();
}

class _RestaurantCardState extends State<_RestaurantCard> {
  bool _isNavigating = false;

  Future<void> _onTap(BuildContext context) async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);
    try {
      final vendor = await FireStoreUtils().getVendorByVendorID(widget.id);
      if (context.mounted) {
        push(context, NewVendorProductsScreen(vendorModel: vendor));
      }
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _onTap(context),
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 12),
        child: Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 100,
                    width: double.infinity,
                    child: CachedNetworkImage(
                      imageUrl: getImageVAlidUrl(widget.imageUrl),
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        height: 100,
                        color: Colors.grey[200],
                        child: const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        height: 100,
                        color: Colors.grey[200],
                        child: Icon(Icons.restaurant, color: Colors.grey[400]),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        if (widget.cuisine.isNotEmpty)
                          Text(
                            widget.cuisine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        Row(
                          children: [
                            if (widget.rating > 0)
                              Text(
                                '${widget.rating.toStringAsFixed(1)} ★',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            if (widget.distance != null) ...[
                              if (widget.rating > 0) const Text(' • '),
                              Text(
                                '${widget.distance} km',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_isNavigating)
                Positioned.fill(
                  child: Container(
                    color: Colors.black54,
                    child: const Center(
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Product list card with Add to Cart.
class ProductListCard extends StatelessWidget {
  const ProductListCard({
    Key? key,
    required this.data,
    required this.cartService,
  }) : super(key: key);

  final Map<String, dynamic> data;
  final AiCartService cartService;

  @override
  Widget build(BuildContext context) {
    final products =
        (data['products'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final message = (data['message'] ?? '') as String? ?? '';

    if (products.isEmpty) {
      return _buildMessageCard(context, message);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ...products.map((p) => _ProductTile(
              product: p,
              cartService: cartService,
            )),
      ],
    );
  }

  Widget _buildMessageCard(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _ProductTile extends StatefulWidget {
  const _ProductTile({
    required this.product,
    required this.cartService,
  });

  final Map<String, dynamic> product;
  final AiCartService cartService;

  @override
  State<_ProductTile> createState() => _ProductTileState();
}

class _ProductTileState extends State<_ProductTile> {
  bool _isAddingToCart = false;
  bool _addedToCart = false;
  bool _isNavigating = false;

  Future<void> _navigateToProduct(BuildContext context) async {
    if (_isNavigating) return;
    final productId = (widget.product['id'] ?? '').toString();
    final vendorId = (widget.product['vendorID'] ?? '').toString();
    if (productId.isEmpty) return;
    setState(() => _isNavigating = true);
    try {
      final firestore = FireStoreUtils();
      ProductModel? product;
      try {
        product = await firestore.getProductByProductID(productId);
      } catch (_) {}
      if (product == null || product.id.isEmpty || !context.mounted) return;
      VendorModel? vendor;
      if (vendorId.isNotEmpty) {
        vendor = await firestore.getVendorByVendorID(vendorId);
      }
      if (vendor == null || !context.mounted) return;
      push(
        context,
        ProductDetailsScreen(
          productModel: product,
          vendorModel: vendor,
        ),
      );
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _addToCart(BuildContext context, String productId) async {
    if (_isAddingToCart || _addedToCart) return;
    setState(() => _isAddingToCart = true);
    try {
      final result = await widget.cartService.addProductById(productId, 1);
      if (!context.mounted) return;
      if (result['success'] == true) {
        setState(() {
          _isAddingToCart = false;
          _addedToCart = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green[400]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Added ${result['product']} to cart'),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${result['error'] ?? 'Failed to add'}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted && !_addedToCart) setState(() => _isAddingToCart = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = (widget.product['id'] ?? '').toString();
    final name = (widget.product['name'] ?? '').toString();
    final price = (widget.product['price'] ?? '0').toString();
    final vendorName = (widget.product['vendorName'] ?? '').toString();
    final imageUrl = (widget.product['imageUrl'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          ListTile(
            onTap: () => _navigateToProduct(context),
            leading: SizedBox(
          width: 56,
          height: 56,
          child: CachedNetworkImage(
            imageUrl: getImageVAlidUrl(imageUrl),
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              color: Colors.grey[100],
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            errorWidget: (_, __, ___) => Container(
              color: Colors.grey[100],
              child: Icon(Icons.fastfood, color: Colors.grey[400]),
            ),
          ),
        ),
        title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            if (vendorName.isNotEmpty) vendorName,
            amountShow(amount: price),
          ].join(' • '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _addedToCart
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.green[600], size: 22),
                  const SizedBox(width: 4),
                  Text(
                    'Added',
                    style: TextStyle(
                      color: Colors.green[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              )
            : _isAddingToCart
                ? const SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: () => _addToCart(context, id),
                    child: const Text('Add to Cart'),
                  ),
          ),
          if (_isNavigating)
            Positioned.fill(
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
                child: const Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Order status stepper card.
class OrderStatusCard extends StatelessWidget {
  const OrderStatusCard({Key? key, required this.data}) : super(key: key);

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final order = data['order'] as Map<String, dynamic>?;
    if (order == null) {
      return Text(
        (data['message'] ?? '').toString(),
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    final steps =
        (order['steps'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final currentStep = (order['currentStep'] ?? 0) is int
        ? order['currentStep'] as int
        : 0;
    final vendor = (order['vendor'] ?? '').toString();
    final eta = (order['estimatedTime'] ?? '').toString();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (vendor.isNotEmpty)
              Text(
                vendor,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            if (eta.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('ETA: $eta min',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            if (steps.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildStepper(context, steps, currentStep),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStepper(
    BuildContext context,
    List<String> steps,
    int currentStep,
  ) {
    final displaySteps =
        steps.take((currentStep + 1).clamp(1, steps.length)).toList();
    return Row(
      children: [
        for (int i = 0; i < displaySteps.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Column(
              children: [
                Icon(
                  i < currentStep ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 20,
                  color: i <= currentStep
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
                const SizedBox(height: 4),
                Text(
                  displaySteps[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// List of active orders.
class OrderListCard extends StatelessWidget {
  const OrderListCard({Key? key, required this.data}) : super(key: key);

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final orders =
        (data['orders'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final message = (data['message'] ?? '') as String? ?? '';

    if (orders.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ...orders.map((o) => _OrderTile(order: o)),
      ],
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});

  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final id = (order['id'] ?? '').toString();
    final vendor = (order['vendor'] ?? '').toString();
    final status = (order['status'] ?? '').toString();
    final total = order['total'];
    final totalStr =
        total != null ? amountShow(amount: total.toString()) : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(vendor.isNotEmpty ? vendor : 'Order'),
        subtitle: Text('$status${totalStr.isNotEmpty ? ' • $totalStr' : ''}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _viewOrder(context, id),
      ),
    );
  }

  Future<void> _viewOrder(BuildContext context, String orderId) async {
    final orderModel = await FireStoreUtils.getOrderByIdOnce(orderId);
    if (orderModel != null && context.mounted) {
      push(
        context,
        OrderDetailsScreen(orderModel: orderModel),
      );
    }
  }
}

/// Booking confirmation card.
class BookingConfirmationCard extends StatelessWidget {
  const BookingConfirmationCard({Key? key, required this.data}) : super(key: key);

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final booking = data['booking'] as Map<String, dynamic>?;
    if (booking == null) {
      return Text(
        (data['message'] ?? '').toString(),
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    final vendor = (booking['vendor'] ?? '').toString();
    final date = (booking['date'] ?? '').toString();
    final time = (booking['time'] ?? '').toString();
    final guests = booking['guests'] ?? 2;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data['message']?.toString() ?? 'Booking confirmed!',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('$vendor'),
            Text('$date at $time • $guests guests'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  push(context, const MyBookingScreen());
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(COLOR_PRIMARY),
                ),
                child: const Text('Manage Booking'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Popular items card.
class PopularListCard extends StatelessWidget {
  const PopularListCard({
    Key? key,
    required this.data,
    required this.cartService,
  }) : super(key: key);

  final Map<String, dynamic> data;
  final AiCartService cartService;

  @override
  Widget build(BuildContext context) {
    final popular =
        (data['popular'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final message = (data['message'] ?? '') as String? ?? '';

    if (popular.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: popular.length,
            itemBuilder: (ctx, i) {
              final p = popular[i];
              return _PopularItemCard(
                id: (p['id'] ?? '').toString(),
                name: (p['name'] ?? '').toString(),
                price: (p['price'] ?? '0').toString(),
                vendorId: (p['vendorID'] ?? '').toString(),
                vendorName: (p['vendorName'] ?? '').toString(),
                imageUrl: (p['imageUrl'] ?? '').toString(),
                orderCount: (p['orderCount'] ?? 0) is int
                    ? p['orderCount'] as int
                    : 0,
                cartService: cartService,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PopularItemCard extends StatefulWidget {
  const _PopularItemCard({
    required this.id,
    required this.name,
    required this.price,
    required this.vendorId,
    required this.vendorName,
    required this.imageUrl,
    required this.orderCount,
    required this.cartService,
  });

  final String id;
  final String name;
  final String price;
  final String vendorId;
  final String vendorName;
  final String imageUrl;
  final int orderCount;
  final AiCartService cartService;

  @override
  State<_PopularItemCard> createState() => _PopularItemCardState();
}

class _PopularItemCardState extends State<_PopularItemCard> {
  bool _isAddingToCart = false;
  bool _addedToCart = false;
  bool _isNavigating = false;

  Future<void> _addToCart(BuildContext context) async {
    if (_isAddingToCart || _addedToCart) return;
    setState(() => _isAddingToCart = true);
    try {
      final result = await widget.cartService.addProductById(widget.id, 1);
      if (!context.mounted) return;
      if (result['success'] == true) {
        setState(() {
          _isAddingToCart = false;
          _addedToCart = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green[400]),
                const SizedBox(width: 8),
                Expanded(child: Text('Added to cart!')),
              ],
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${result['error'] ?? 'Failed to add'}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted && !_addedToCart) setState(() => _isAddingToCart = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _onTap(context),
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 12),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      SizedBox(
                        height: 80,
                        width: double.infinity,
                        child: CachedNetworkImage(
                          imageUrl: getImageVAlidUrl(widget.imageUrl),
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            height: 80,
                            color: Colors.grey[100],
                            child: const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            height: 80,
                            color: Colors.grey[100],
                            child: Icon(
                              Icons.fastfood,
                              color: Colors.grey[400],
                            ),
                          ),
                        ),
                      ),
                      if (widget.orderCount > 0)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${widget.orderCount} orders',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        Text(
                          amountShow(amount: widget.price),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _addedToCart
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        color: Colors.green[600],
                                        size: 18,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Added',
                                        style: TextStyle(
                                          color: Colors.green[600],
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  )
                                : _isAddingToCart
                                    ? const SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: Center(
                                          child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        ),
                                      )
                                    : IconButton(
                                        icon: Icon(
                                          Icons.add_shopping_cart,
                                          size: 20,
                                          color: Color(COLOR_PRIMARY),
                                        ),
                                        onPressed: () => _addToCart(context),
                                        tooltip: 'Add to cart',
                                        splashRadius: 20,
                                      ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_isNavigating)
                Positioned.fill(
                  child: Container(
                    color: Colors.black54,
                    child: const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onTap(BuildContext context) async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);
    try {
      final firestore = FireStoreUtils();
      ProductModel? product;
      try {
        product = await firestore.getProductByProductID(widget.id);
      } catch (_) {}
      if (product == null || product.id.isEmpty || !context.mounted) return;
      VendorModel? vendor;
      if (widget.vendorId.isNotEmpty) {
        vendor = await firestore.getVendorByVendorID(widget.vendorId);
      }
      if (vendor == null || !context.mounted) return;
      push(
        context,
        ProductDetailsScreen(
          productModel: product,
          vendorModel: vendor,
        ),
      );
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }
}

/// Coupon result card.
class CouponResultCard extends StatelessWidget {
  const CouponResultCard({Key? key, required this.data}) : super(key: key);

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final code = data['bestCoupon']?.toString() ?? '';
    final discount = (data['discount'] ?? 0) is num
        ? (data['discount'] as num).toDouble()
        : 0.0;
    final message = data['message']?.toString() ?? '';

    if (code.isEmpty && discount <= 0) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message.isNotEmpty ? message : 'No coupons available.',
          style: Theme.of(context).textTheme.bodyMedium,
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (code.isNotEmpty)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Code: $code',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Coupon code copied'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
                  ),
                ],
              ),
            if (discount > 0)
              Text(
                'Saves ${amountShow(amount: discount.toString())}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
          ],
        ),
      ),
    );
  }
}
