import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/performance_logger.dart';
import '../constants.dart';
import '../model/ProductModel.dart';
import '../services/localDatabase.dart';

class AddIconButton extends StatefulWidget {
  final ProductModel productModel;
  final double size;
  final EdgeInsetsGeometry? margin;
  final Color? iconColor;
  final Color? backgroundColor;
  final Color? textColor;
  final VoidCallback? onCartUpdated;
  final bool isRestaurantOpen;

  const AddIconButton({
    Key? key,
    required this.productModel,
    this.size = 30.0,
    this.margin,
    this.iconColor,
    this.backgroundColor,
    this.textColor,
    this.onCartUpdated,
    this.isRestaurantOpen = true,
  }) : super(key: key);

  @override
  State<AddIconButton> createState() => _AddIconButtonState();
}

class _AddIconButtonState extends State<AddIconButton>
    with TickerProviderStateMixin {
  late AnimationController _expandController;
  late AnimationController _tapController;
  late Animation<double> _widthAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  int _quantity = 0;
  bool _showCounter = false;
  List<CartProduct> _cartProducts = [];

  @override
  void initState() {
    super.initState();

    // Animation for expanding/collapsing the counter
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    // Animation for tap feedback
    _tapController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _widthAnimation = Tween<double>(
      begin: 1.0,
      end: 2.8, // 2.8x width when expanded (84px when size = 30px)
    ).animate(CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOut, // Faster, snappier curve
    ));

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.9,
    ).animate(CurvedAnimation(
      parent: _tapController,
      curve: Curves.easeInOut,
    ));

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOut, // Faster, snappier curve
    ));

    _loadCartQuantity();
  }

  @override
  void dispose() {
    _expandController.dispose();
    _tapController.dispose();
    super.dispose();
  }

  void _loadCartQuantity() async {
    final cartDatabase = Provider.of<CartDatabase>(context, listen: false);
    final products = await cartDatabase.allCartProducts;
    setState(() {
      _cartProducts = products;
      _quantity = _getProductQuantity();

      // Show counter immediately if quantity > 0, then animate
      _showCounter = _quantity > 0;
      if (_quantity > 0) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    });
  }

  int _getProductQuantity() {
    final productId = widget.productModel.id +
        "~" +
        (widget.productModel.variantInfo != null
            ? widget.productModel.variantInfo!.variantId.toString()
            : "");

    final cartItem = _cartProducts.firstWhere(
      (product) => product.id == productId,
      orElse: () => CartProduct(
        id: '',
        name: '',
        photo: '',
        price: '',
        vendorID: '',
        quantity: 0,
        category_id: '',
        addedAt: DateTime.now(),
      ),
    );

    return cartItem.quantity;
  }

  Future<bool> _checkVendorConflict(
      BuildContext context, CartDatabase cartDatabase) async {
    final products = await cartDatabase.allCartProducts;

    if (products.isEmpty) {
      return true; // No conflict, cart is empty
    }

    // Check if any product has different vendorID
    final firstVendorId = products.first.vendorID;
    final hasConflict = firstVendorId != widget.productModel.vendorID;

    if (!hasConflict) {
      return true; // Same restaurant, no conflict
    }

    // Show confirmation dialog
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Replace cart items?'),
          content: Text(
            'Your cart contains items from a different restaurant. Do you want to clear your cart and add this item?'
                ,
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(COLOR_PRIMARY),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(COLOR_PRIMARY),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text('Add'),
            ),
          ],
        );
      },
    );

    if (shouldClear == true) {
      await cartDatabase.deleteAllProducts();
      // Reset local state after clearing cart
      setState(() {
        _cartProducts.clear();
        _quantity = 0;
        _showCounter = false;
      });
      return true;
    }

    return false; // User cancelled
  }

  void _addToCart() async {
    if (_quantity >= 99) return;

    // Check if restaurant is open before adding
    if (!widget.isRestaurantOpen) {
      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Restaurant Closed'),
            content: Text('Restaurant is currently closed. Please try again during operating hours.'),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(COLOR_PRIMARY),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text('OK'),
              ),
            ],
          );
        },
      );
      return;
    }

    // Check for vendor conflict before adding
    final cartDatabase = Provider.of<CartDatabase>(context, listen: false);
    final canAdd = await _checkVendorConflict(context, cartDatabase);

    if (!canAdd) {
      return; // User cancelled, don't add
    }

    // Show counter immediately for instant visual feedback
    setState(() {
      _quantity = _quantity + 1;
      _showCounter = true;
    });

    // Start or continue width expansion animation
    if (_expandController.value == 0.0) {
      // If starting from 0, jump to minimum width (2.0x) then animate to full width
      _expandController.value = 0.71; // 2.0 / 2.8 = 0.71 (2.0x out of 2.8x max)
      _expandController.forward();
    } else if (_expandController.value < 1.0) {
      // Continue animation if already started
      _expandController.forward();
    }

    // Tap animation
    _tapController.forward().then((_) {
      _tapController.reverse();
    });

    // Then sync with actual cart state
    final stopwatch = Stopwatch()..start();
    await cartDatabase.addProduct(widget.productModel, cartDatabase, true);
    stopwatch.stop();
    PerformanceLogger.logAddToCart(stopwatch.elapsed);

    // Trigger cart update callback to refresh parent UI
    if (widget.onCartUpdated != null) {
      widget.onCartUpdated!();
    }

    // Don't call _loadCartQuantity() here as it resets the state
    // The optimistic update above is sufficient for immediate feedback
    // The cart will be synced when the widget rebuilds naturally
  }

  void _removeFromCart() async {
    if (_quantity <= 0) return;

    final wasQuantityOne = _quantity == 1;

    // Update quantity immediately for instant UI feedback
    setState(() {
      _quantity = _quantity - 1;
      if (_quantity == 0) {
        _showCounter = false;
        _expandController.reverse();
      }
    });

    // Tap animation
    _tapController.forward().then((_) {
      _tapController.reverse();
    });

    final cartDatabase = Provider.of<CartDatabase>(context, listen: false);
    final productId = widget.productModel.id +
        "~" +
        (widget.productModel.variantInfo != null
            ? widget.productModel.variantInfo!.variantId.toString()
            : "");

    final stopwatch = Stopwatch()..start();
    if (wasQuantityOne) {
      await cartDatabase.removeProduct(productId);
      stopwatch.stop();
      PerformanceLogger.logRemoveFromCart(stopwatch.elapsed);
    } else {
      final cartItem = _cartProducts.firstWhere(
        (product) => product.id == productId,
      );
      await cartDatabase.updateProduct(CartProduct(
        id: cartItem.id,
        name: cartItem.name,
        photo: cartItem.photo,
        price: cartItem.price,
        vendorID: cartItem.vendorID,
        quantity: cartItem.quantity - 1,
        category_id: cartItem.category_id,
        extras_price: cartItem.extras_price,
        extras: cartItem.extras,
        discountPrice: cartItem.discountPrice,
        addedAt: cartItem.addedAt,
      ));
      stopwatch.stop();
      PerformanceLogger.logUpdateQuantity(stopwatch.elapsed);
    }

    // Don't call _loadCartQuantity() here as it resets the state
    // The optimistic update above is sufficient for immediate feedback
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_expandController, _tapController]),
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            height: widget.size,
            // When showing counter immediately, ensure minimum usable width
            // This makes it responsive right away, then animates to full width
            width: _showCounter && _widthAnimation.value < 2.0
                ? widget.size * 2.0 // Minimum width for counter to be tappable
                : widget.size * _widthAnimation.value,
            margin: widget.margin ?? const EdgeInsets.all(6.0),
            decoration: BoxDecoration(
              color: widget.backgroundColor ?? Colors.white,
              borderRadius: BorderRadius.circular(widget.size / 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 6.0,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: _showCounter ? _buildExpandedCounter() : _buildPlusOnly(),
          ),
        );
      },
    );
  }

  Widget _buildPlusOnly() {
    return Center(
      child: GestureDetector(
        onTap: _addToCart,
        child: Icon(
          Icons.add,
          color: widget.iconColor ?? Color(COLOR_PRIMARY),
          size: widget.size * 0.67,
        ),
      ),
    );
  }

  Widget _buildExpandedCounter() {
    // Show counter immediately at full opacity when _showCounter is true
    // Only use opacity animation when collapsing (fade out)
    final opacity = _showCounter
        ? 1.0
        : (_opacityAnimation.value > 0.1 ? _opacityAnimation.value : 0.0);

    return Opacity(
      opacity: opacity,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: widget.size * 0.1),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Minus button
            GestureDetector(
              onTap: _removeFromCart,
              child: Icon(
                Icons.remove,
                color: widget.iconColor ?? Color(COLOR_PRIMARY),
                size: widget.size * 0.6,
              ),
            ),
            // Quantity number
            Text(
              '$_quantity',
              style: TextStyle(
                color: widget.textColor ?? Color(COLOR_PRIMARY),
                fontSize: widget.size * 0.45,
                fontWeight: FontWeight.bold,
              ),
            ),
            // Plus button
            GestureDetector(
              onTap: _addToCart,
              child: Icon(
                Icons.add,
                color: widget.iconColor ?? Color(COLOR_PRIMARY),
                size: widget.size * 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
