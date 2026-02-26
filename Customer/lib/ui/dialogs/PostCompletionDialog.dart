import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/FavouriteModel.dart';
import 'package:foodie_customer/model/OrderModel.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/localDatabase.dart';
import 'package:foodie_customer/ui/cartScreen/CartScreen.dart';
import 'package:foodie_customer/ui/reviewScreen.dart/reviewScreen.dart';
import 'package:foodie_customer/userPrefrence.dart';
import 'package:provider/provider.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:intl/intl.dart';

class PostCompletionDialog extends StatefulWidget {
  final OrderModel order;

  const PostCompletionDialog({Key? key, required this.order}) : super(key: key);

  static Future<void> show(BuildContext context, OrderModel order) async {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return PostCompletionDialog(order: order);
      },
    );
  }

  @override
  State<PostCompletionDialog> createState() => _PostCompletionDialogState();
}

class _PostCompletionDialogState extends State<PostCompletionDialog> {
  final FireStoreUtils _fireStoreUtils = FireStoreUtils();
  bool _isRestaurantFavorite = false;
  bool _isProcessingReorder = false;
  bool _isProcessingFavorite = false;
  Set<String> _selectedFeedbackTags = {};
  bool? _orderAccuracy;
  double? _confirmationSpeedRating;
  bool _savingConfirmationFeedback = false;
  final TextEditingController _reportController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkFavoriteStatus();
  }

  @override
  void dispose() {
    _reportController.dispose();
    super.dispose();
  }

  Future<void> _checkFavoriteStatus() async {
    if (MyAppState.currentUser == null) return;
    try {
      final favorites = await _fireStoreUtils.getFavouriteRestaurant(
          MyAppState.currentUser!.userID);
      setState(() {
        _isRestaurantFavorite = favorites.any(
          (fav) => fav.restaurantId == widget.order.vendorID,
        );
      });
    } catch (e) {
      debugPrint('Error checking favorite status: $e');
    }
  }

  void _dismissDialog() {
    // Mark dialog as shown
    if (MyAppState.currentUser != null) {
      UserPreference.markCompletionDialogShown(
        MyAppState.currentUser!.userID,
        widget.order.id,
      );
    }
    Navigator.of(context).pop();
  }

  Future<void> _handleRateProduct() async {
    if (widget.order.products.isEmpty) {
      showAlertDialog(
        context,
        'No Products',
        'This order has no products to rate.',
        true,
      );
      return;
    }

    // Navigate to review screen for first product
    final firstProduct = widget.order.products.first;
    _dismissDialog();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ReviewScreen(
          product: firstProduct,
          orderId: widget.order.id,
        ),
      ),
    );
  }

  Future<void> _handleReorder() async {
    if (_isProcessingReorder) return;
    setState(() => _isProcessingReorder = true);

    try {
      showProgress(context, "Please wait", false);

      if (widget.order.products.isEmpty) {
        hideProgress();
        showAlertDialog(
          context,
          "Reorder Failed",
          "This order has no products to reorder.",
          true,
        );
        setState(() => _isProcessingReorder = false);
        return;
      }

      // Clear current cart
      try {
        await Provider.of<CartDatabase>(context, listen: false)
            .deleteAllProducts()
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint("Error clearing cart: $e");
      }

      final cartDatabase = Provider.of<CartDatabase>(context, listen: false);
      int successCount = 0;
      int failCount = 0;
      List<String> failedProducts = [];

      // Re-add each product
      for (final product in widget.order.products) {
        try {
          final validatedProduct = _validateAndTransformCartProduct(product);
          if (validatedProduct != null) {
            await cartDatabase
                .reAddProduct(validatedProduct)
                .timeout(const Duration(seconds: 5));
            successCount++;
          } else {
            failCount++;
            failedProducts.add(product.name);
          }
        } catch (e) {
          failCount++;
          failedProducts.add(product.name);
          debugPrint("Error adding product ${product.name}: $e");
        }
      }

      hideProgress();

      if (successCount > 0 && failCount == 0) {
        _dismissDialog();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CartScreen(fromContainer: false),
          ),
        );
      } else if (successCount > 0 && failCount > 0) {
        showAlertDialog(
          context,
          "Partial Reorder",
          "$successCount product(s) added to cart. $failCount product(s) could not be added: ${failedProducts.join(', ')}",
          true,
        );
        _dismissDialog();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CartScreen(fromContainer: false),
          ),
        );
      } else {
        showAlertDialog(
          context,
          "Reorder Failed",
          "Unable to add products to cart. Please try again.",
          true,
        );
      }
    } catch (e) {
      hideProgress();
      showAlertDialog(
        context,
        "Reorder Failed",
        "An error occurred while reordering. Please try again.",
        true,
      );
    } finally {
      setState(() => _isProcessingReorder = false);
    }
  }

  CartProduct? _validateAndTransformCartProduct(CartProduct product) {
    try {
      if (product.id.isEmpty ||
          product.name.isEmpty ||
          product.vendorID.isEmpty ||
          product.price.isEmpty) {
        return null;
      }

      String categoryId = product.category_id ?? product.id.split('~').first;
      if (categoryId.isEmpty) {
        categoryId = product.id;
      }

      String? extrasString;
      if (product.extras != null) {
        if (product.extras is List) {
          final extrasList =
              (product.extras as List).map((e) => e.toString()).toList();
          extrasString = extrasList.join(',');
        } else if (product.extras is String) {
          extrasString = product.extras as String;
        } else {
          extrasString = product.extras.toString();
        }
      }

      return CartProduct(
        id: product.id,
        category_id: categoryId,
        name: product.name,
        photo: product.photo.isNotEmpty ? product.photo : '',
        price: product.price,
        discountPrice: product.discountPrice ?? "",
        vendorID: product.vendorID,
        quantity: product.quantity > 0 ? product.quantity : 1,
        extras: extrasString,
        variant_info: product.variant_info,
      );
    } catch (e) {
      debugPrint("Error validating product: $e");
      return null;
    }
  }

  Future<void> _handleToggleFavorite() async {
    if (_isProcessingFavorite || MyAppState.currentUser == null) return;
    setState(() => _isProcessingFavorite = true);

    try {
      final favouriteModel = FavouriteModel(
        restaurantId: widget.order.vendorID,
        userId: MyAppState.currentUser!.userID,
      );

      if (_isRestaurantFavorite) {
        _fireStoreUtils.removeFavouriteRestaurant(favouriteModel);
        setState(() => _isRestaurantFavorite = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Removed from favorites')),
        );
      } else {
        _fireStoreUtils.setFavouriteRestaurant(favouriteModel);
        setState(() => _isRestaurantFavorite = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Added to favorites')),
        );
      }
    } catch (e) {
      showAlertDialog(
        context,
        'Error',
        'Failed to update favorites. Please try again.',
        true,
      );
    } finally {
      setState(() => _isProcessingFavorite = false);
    }
  }

  Future<void> _handleReportDriver() async {
    if (widget.order.driverID == null || widget.order.driverID!.isEmpty) {
      showAlertDialog(
        context,
        'No Driver',
        'This order has no assigned driver.',
        true,
      );
      return;
    }

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report Driver'),
        content: TextField(
          controller: _reportController,
          decoration: const InputDecoration(
            hintText: 'Please describe the issue...',
            border: OutlineInputBorder(),
          ),
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (_reportController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a complaint')),
                );
                return;
              }

              try {
                await FirebaseFirestore.instance.collection(REPORTS).add({
                  'orderId': widget.order.id,
                  'driverId': widget.order.driverID,
                  'userId': MyAppState.currentUser?.userID ?? '',
                  'complaint': _reportController.text.trim(),
                  'createdAt': FieldValue.serverTimestamp(),
                  'type': 'driver_report',
                });

                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Report submitted successfully')),
                );
                _reportController.clear();
              } catch (e) {
                showAlertDialog(
                  context,
                  'Error',
                  'Failed to submit report. Please try again.',
                  true,
                );
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSaveFeedbackTags() async {
    if (_selectedFeedbackTags.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection(ORDERS)
          .doc(widget.order.id)
          .update({
        'feedbackTags': _selectedFeedbackTags.toList(),
        'feedbackUpdatedAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Feedback saved')),
      );
    } catch (e) {
      debugPrint('Error saving feedback tags: $e');
    }
  }

  Future<void> _handleOrderAccuracy(bool isAccurate) async {
    setState(() => _orderAccuracy = isAccurate);

    try {
      await FirebaseFirestore.instance
          .collection(ORDERS)
          .doc(widget.order.id)
          .update({
        'orderAccuracy': isAccurate,
        'accuracyUpdatedAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isAccurate
              ? 'Thank you for confirming!'
              : 'We apologize for the inconvenience'),
        ),
      );
    } catch (e) {
      debugPrint('Error saving order accuracy: $e');
    }
  }

  Future<void> _handleConfirmationSpeedRating(double rating) async {
    setState(() {
      _confirmationSpeedRating = rating;
      _savingConfirmationFeedback = true;
    });
    try {
      await FirebaseFirestore.instance.collection(ORDER_FEEDBACK).add({
        'orderId': widget.order.id,
        'vendorId': widget.order.vendorID,
        'userId': MyAppState.currentUser?.userID ?? '',
        'confirmationSpeedRating': rating.toInt(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thank you for your feedback!')),
        );
      }
    } catch (e) {
      debugPrint('Error saving confirmation feedback: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save feedback: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingConfirmationFeedback = false);
    }
  }

  void _toggleFeedbackTag(String tag) {
    setState(() {
      if (_selectedFeedbackTags.contains(tag)) {
        _selectedFeedbackTags.remove(tag);
      } else {
        _selectedFeedbackTags.add(tag);
      }
    });
    _handleSaveFeedbackTags();
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy');
    final orderDate = dateFormat.format(widget.order.createdAt.toDate());

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Color(COLOR_PRIMARY).withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order Completed! 🎉',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Poppinsm',
                            color: isDarkMode(context)
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.order.vendor.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontFamily: 'Poppinsr',
                            color: isDarkMode(context)
                                ? Colors.white70
                                : Colors.black87,
                          ),
                        ),
                        Text(
                          orderDate,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'Poppinsr',
                            color: isDarkMode(context)
                                ? Colors.white60
                                : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _dismissDialog,
                    color: isDarkMode(context) ? Colors.white : Colors.black,
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Primary CTA: Rate Product
                    ElevatedButton(
                      onPressed: _handleRateProduct,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(COLOR_PRIMARY),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Rate Your Experience',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppinsm',
                          color: Colors.white,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Confirmation speed feedback
                    Text(
                      'How fast did the restaurant confirm your order?',
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'Poppinsr',
                        color: isDarkMode(context)
                            ? Colors.white70
                            : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    RatingBar.builder(
                      initialRating: _confirmationSpeedRating ?? 0,
                      minRating: 1,
                      direction: Axis.horizontal,
                      allowHalfRating: false,
                      itemCount: 5,
                      itemSize: 28,
                      itemPadding:
                          const EdgeInsets.symmetric(horizontal: 2),
                      itemBuilder: (context, _) => Icon(
                        Icons.star,
                        color: Color(COLOR_PRIMARY),
                      ),
                      onRatingUpdate: (rating) {
                        _handleConfirmationSpeedRating(rating);
                      },
                      ignoreGestures: _savingConfirmationFeedback,
                    ),
                    const SizedBox(height: 24),

                    // Secondary Actions
                    Text(
                      'More Options',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppinsm',
                        color: isDarkMode(context)
                            ? Colors.white70
                            : Colors.black54,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Re-order
                    _buildActionButton(
                      icon: Icons.repeat,
                      label: 'Re-order',
                      onTap: _isProcessingReorder ? null : _handleReorder,
                      isLoading: _isProcessingReorder,
                    ),

                    const SizedBox(height: 8),

                    // Favorites
                    _buildActionButton(
                      icon: _isRestaurantFavorite
                          ? Icons.favorite
                          : Icons.favorite_border,
                      label: _isRestaurantFavorite
                          ? 'Remove from Favorites'
                          : 'Save to Favorites',
                      onTap: _isProcessingFavorite ? null : _handleToggleFavorite,
                      isLoading: _isProcessingFavorite,
                      iconColor: _isRestaurantFavorite
                          ? Color(COLOR_PRIMARY)
                          : null,
                    ),

                    const SizedBox(height: 8),

                    // Report Driver
                    if (widget.order.driverID != null &&
                        widget.order.driverID!.isNotEmpty)
                      _buildActionButton(
                        icon: Icons.report_problem,
                        label: 'Report Driver',
                        onTap: _handleReportDriver,
                      ),

                    if (widget.order.driverID != null &&
                        widget.order.driverID!.isNotEmpty)
                      const SizedBox(height: 8),

                    // Quick Feedback Tags
                    Text(
                      'Quick Feedback',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'Poppinsr',
                        color: isDarkMode(context)
                            ? Colors.white60
                            : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        'Great Food',
                        'Fast Delivery',
                        'Poor Quality',
                        'Late Delivery',
                      ].map((tag) {
                        final isSelected = _selectedFeedbackTags.contains(tag);
                        return FilterChip(
                          label: Text(tag),
                          selected: isSelected,
                          onSelected: (_) => _toggleFeedbackTag(tag),
                          selectedColor: Color(COLOR_PRIMARY).withOpacity(0.3),
                          checkmarkColor: Color(COLOR_PRIMARY),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 16),

                    // Order Accuracy
                    Text(
                      'Was your order accurate?',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'Poppinsr',
                        color: isDarkMode(context)
                            ? Colors.white60
                            : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _handleOrderAccuracy(true),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: _orderAccuracy == true
                                    ? Color(COLOR_PRIMARY)
                                    : Colors.grey,
                                width: _orderAccuracy == true ? 2 : 1,
                              ),
                              backgroundColor: _orderAccuracy == true
                                  ? Color(COLOR_PRIMARY).withOpacity(0.1)
                                  : null,
                            ),
                            child: Text(
                              'Yes',
                              style: TextStyle(
                                color: _orderAccuracy == true
                                    ? Color(COLOR_PRIMARY)
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _handleOrderAccuracy(false),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: _orderAccuracy == false
                                    ? Colors.red
                                    : Colors.grey,
                                width: _orderAccuracy == false ? 2 : 1,
                              ),
                              backgroundColor: _orderAccuracy == false
                                  ? Colors.red.withOpacity(0.1)
                                  : null,
                            ),
                            child: Text(
                              'No',
                              style: TextStyle(
                                color: _orderAccuracy == false
                                    ? Colors.red
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Dismiss button
                    TextButton(
                      onPressed: _dismissDialog,
                      child: Text(
                        'Maybe Later',
                        style: TextStyle(
                          fontFamily: 'Poppinsr',
                          color: isDarkMode(context)
                              ? Colors.white70
                              : Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool isLoading = false,
    Color? iconColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isDarkMode(context)
                ? Colors.grey.shade700
                : Colors.grey.shade300,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                icon,
                size: 20,
                color: iconColor ??
                    (isDarkMode(context) ? Colors.white70 : Colors.black54),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: 'Poppinsm',
                  color: isDarkMode(context) ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

