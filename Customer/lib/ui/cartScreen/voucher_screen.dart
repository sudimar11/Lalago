import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/offer_model.dart';
import 'package:foodie_customer/services/coupon_service.dart';
import 'package:foodie_customer/services/helper.dart';

class VoucherScreen extends StatefulWidget {
  final double subTotal;
  final String? vendorId;
  final int totalItemCount;
  final String? prefillCode;

  const VoucherScreen({
    super.key,
    required this.subTotal,
    required this.vendorId,
    required this.totalItemCount,
    this.prefillCode,
  });

  @override
  State<VoucherScreen> createState() => _VoucherScreenState();
}

class _VoucherScreenState extends State<VoucherScreen> {
  final List<OfferModel> _coupons = [];
  bool _isLoading = true;
  bool _isApplying = false;
  String? _error;
  String? _applyError;
  String? _applyingCode;
  late final TextEditingController _codeController;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.prefillCode ?? '');
    _loadCoupons();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadCoupons() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userId = MyAppState.currentUser?.userID;
      final coupons = await CouponService.getActiveCoupons(
        widget.vendorId,
        userId: userId,
      );
      if (!mounted) return;
      setState(() {
        _coupons
          ..clear()
          ..addAll(coupons);
        _isLoading = false;
      });
    } catch (e) {
      log('Error loading vouchers: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load vouchers. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _applyCode(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) {
      setState(() {
        _applyError = 'Please enter a voucher code';
      });
      return;
    }

    setState(() {
      _isApplying = true;
      _applyError = null;
      _applyingCode = normalized;
    });

    try {
      final userId = MyAppState.currentUser?.userID ?? '';
      final validation = await CouponService.validateCoupon(
        normalized,
        widget.subTotal,
        userId,
        widget.vendorId,
        totalItemCount: widget.totalItemCount,
      );

      if (!mounted) return;

      if (validation['valid'] == true) {
        Navigator.pop(context, normalized);
        return;
      }

      setState(() {
        _applyError = validation['error'] as String? ?? 'Voucher not applicable';
        _isApplying = false;
        _applyingCode = null;
      });
    } catch (e) {
      log('Error applying voucher: $e');
      if (!mounted) return;
      setState(() {
        _applyError = 'Something went wrong. Please try again.';
        _isApplying = false;
        _applyingCode = null;
      });
    }
  }

  String _getDiscountText(OfferModel coupon) {
    if (coupon.discount == null || coupon.discountType == null) {
      return '';
    }
    final discountValue = double.tryParse(coupon.discount!) ?? 0.0;
    final isPercentage = coupon.discountType!.toLowerCase() == 'percentage' ||
        coupon.discountType!.toLowerCase() == 'percent';

    if (isPercentage) {
      return '${discountValue.toStringAsFixed(0)}% OFF';
    }
    return '${amountShow(amount: discountValue.toStringAsFixed(2))} OFF';
  }

  String _getValidityText(OfferModel coupon) {
    final validUntil = coupon.validUntil ?? coupon.expireOfferDate;
    if (validUntil == null) return 'Valid now';
    final formatter = DateFormat('dd MMM yyyy');
    return 'Use by ${formatter.format(validUntil.toDate())}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkMode(context);

    return Scaffold(
      backgroundColor: isDark ? const Color(DARK_COLOR) : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(DARK_COLOR) : Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : Colors.black,
        ),
        title: Text(
          'Apply a voucher',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator.adaptive(),
            )
          : _error != null
              ? Center(
                  child: SelectableText.rich(
                    TextSpan(
                      text: _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextField(
                            controller: _codeController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              hintText: 'Enter a voucher code',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onSubmitted: (_) =>
                                _applyCode(_codeController.text),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isApplying
                                  ? null
                                  : () => _applyCode(_codeController.text),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color(COLOR_PRIMARY),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: _isApplying
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child:
                                          CircularProgressIndicator.adaptive(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          Colors.white,
                                        ),
                                      ),
                                    )
                                  : const Text(
                                      'Apply',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'Poppinsm',
                                      ),
                                    ),
                            ),
                          ),
                          if (_applyError != null) ...[
                            const SizedBox(height: 8),
                            SelectableText.rich(
                              TextSpan(
                                text: _applyError!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadCoupons,
                        color: Color(COLOR_PRIMARY),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _coupons.length,
                          itemBuilder: (context, index) {
                            final coupon = _coupons[index];
                            final minAmount = coupon.minOrderAmount ?? 0.0;
                            final amountGap = minAmount - widget.subTotal;
                            final needsAmount = amountGap > 0;

                            final minItems = coupon.minItems;
                            final needsItems = minItems != null &&
                                widget.totalItemCount < minItems;
                            final itemsGap = needsItems
                                ? minItems - widget.totalItemCount
                                : null;

                            final helperText = needsItems
                                ? 'Add $itemsGap more item(s) to use this voucher'
                                : needsAmount
                                    ? 'Add ${amountShow(amount: amountGap.toStringAsFixed(2))} more to use this voucher'
                                    : null;

                            final code = coupon.offerCode ?? '';
                            final isApplying = _applyingCode == code;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(DarkContainerColor)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? const Color(DarkContainerBorderColor)
                                      : Colors.grey.shade200,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (helperText != null)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 8),
                                      child: Text(
                                        helperText,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.local_offer_outlined,
                                        color: Colors.pink,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              coupon.title ??
                                                  coupon.offerCode ??
                                                  'Voucher',
                                              style: TextStyle(
                                                fontFamily: 'Poppinsm',
                                                fontSize: 14,
                                                color: isDark
                                                    ? Colors.white
                                                    : Colors.black,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _getDiscountText(coupon),
                                              style: TextStyle(
                                                fontFamily: 'Poppinsm',
                                                fontSize: 13,
                                                color: Color(COLOR_PRIMARY),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _getValidityText(coupon),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDark
                                                    ? Colors.grey.shade400
                                                    : Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      ElevatedButton(
                                        onPressed: needsAmount ||
                                                needsItems ||
                                                isApplying
                                            ? null
                                            : () => _applyCode(code),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Color(COLOR_PRIMARY),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 10,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                        ),
                                        child: isApplying
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator
                                                        .adaptive(
                                                  strokeWidth: 2,
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                          Color>(
                                                    Colors.white,
                                                  ),
                                                ),
                                              )
                                            : const Text(
                                                'Apply',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                ),
                                              ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
