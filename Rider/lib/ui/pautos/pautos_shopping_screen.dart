import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/model/PautosOrderModel.dart';
import 'package:foodie_driver/model/SubstitutionRequestModel.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:foodie_driver/services/pautos_service.dart';

class PautosShoppingScreen extends StatefulWidget {
  final String orderId;
  final PautosOrderModel order;

  const PautosShoppingScreen({
    Key? key,
    required this.orderId,
    required this.order,
  }) : super(key: key);

  @override
  State<PautosShoppingScreen> createState() => _PautosShoppingScreenState();
}

class _PautosShoppingScreenState extends State<PautosShoppingScreen> {
  final _costController = TextEditingController();
  final _imagePicker = ImagePicker();
  Set<int> _itemsFound = {};
  File? _receiptFile;
  bool _isSubmitting = false;

  List<String> get _items {
    final text = widget.order.shoppingList.trim();
    if (text.isEmpty) return [];
    return text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  @override
  void dispose() {
    _costController.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt(ImageSource source) async {
    final xFile = await _imagePicker.pickImage(source: source);
    if (xFile != null && mounted) {
      setState(() => _receiptFile = File(xFile.path));
    }
  }

  Future<void> _showSubstitutionDialog(
    BuildContext context, {
    required String originalItem,
    required int originalItemIndex,
  }) async {
    final proposedController = TextEditingController();
    final priceController = TextEditingController();

    final result = await showDialog<({String proposed, double price})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Propose substitution'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Original: $originalItem'),
              const SizedBox(height: 16),
              TextField(
                controller: proposedController,
                decoration: const InputDecoration(
                  labelText: 'Proposed item',
                  hintText: 'Alternative item',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Proposed price',
                  prefixText: '${currencyModel?.symbol ?? '₱'} ',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final proposed = proposedController.text.trim();
              if (proposed.isEmpty) return;
              final price = double.tryParse(priceController.text.trim());
              if (price == null || price < 0) return;
              Navigator.pop(ctx, (proposed: proposed, price: price));
            },
            child: const Text('Propose'),
          ),
        ],
      ),
    );

    proposedController.dispose();
    priceController.dispose();

    if (result == null || !mounted) return;

    final proposed = result.proposed;
    final price = result.price;

    final id = await PautosService.createSubstitutionRequest(
      widget.orderId,
      originalItem,
      originalItemIndex,
      proposed,
      price,
    );

    if (!mounted) return;
    if (id != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Substitution proposed. Waiting for customer.'),
          backgroundColor: Colors.blue,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to propose substitution'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _completeCheckout() async {
    final costStr = _costController.text.trim();
    if (costStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter actual cost')),
      );
      return;
    }
    final cost = double.tryParse(costStr);
    if (cost == null || cost <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      String? receiptUrl;
      if (_receiptFile != null) {
        receiptUrl = await FireStoreUtils.uploadPautosReceipt(
          _receiptFile!,
          widget.orderId,
        );
      }

      final itemsFoundList = _itemsFound.toList()..sort();
      final ok = await PautosService.completeShopping(
        widget.orderId,
        cost,
        receiptUrl,
        itemsFoundList.isEmpty ? null : itemsFoundList,
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Checkout complete. Ready for delivery.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to complete checkout'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PAUTOS Shopping'),
        backgroundColor: Color(COLOR_PRIMARY),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Max budget: ${amountShow(amount: widget.order.maxBudget.toString())}',
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode(context) ? Colors.white70 : Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Shopping List',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDarkMode(context)
                      ? Color(DARK_CARD_BG_COLOR)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.order.shoppingList.isEmpty
                      ? 'No items'
                      : widget.order.shoppingList,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDarkMode(context)
                        ? Colors.white70
                        : Colors.black87,
                  ),
                ),
              )
            else
              ...items.asMap().entries.map((e) {
                final i = e.key;
                final item = e.value;
                final found = _itemsFound.contains(i);
                return ListTile(
                  leading: Checkbox(
                    value: found,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _itemsFound.add(i);
                        } else {
                          _itemsFound.remove(i);
                        }
                      });
                    },
                  ),
                  title: Text(
                    item,
                    style: TextStyle(
                      fontSize: 14,
                      decoration: found ? TextDecoration.lineThrough : null,
                      color: isDarkMode(context)
                          ? Colors.white70
                          : Colors.black87,
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => _showSubstitutionDialog(
                              context,
                              originalItem: item,
                              originalItemIndex: i,
                            ),
                    child: const Text('Item unavailable?'),
                  ),
                );
              }),
            const SizedBox(height: 24),
            StreamBuilder<List<SubstitutionRequestModel>>(
              stream: PautosService.getSubstitutionRequestsStream(widget.orderId),
              builder: (context, subSnap) {
                final subs = subSnap.data ?? [];
                final hasPending =
                    subs.any((s) => s.status == 'pending');
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (subs.isNotEmpty) ...[
                      const Text(
                        'Substitutions',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...subs.map((s) {
                        final statusColor = s.isPending
                            ? Colors.orange
                            : s.isApproved
                                ? Colors.green
                                : Colors.red;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDarkMode(context)
                                ? Color(DARK_CARD_BG_COLOR)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: statusColor.withOpacity(0.5)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${s.originalItem} → ${s.proposedItem}'),
                              Text(
                                '${amountShow(amount: s.proposedPrice.toString())} '
                                '• ${s.status}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: statusColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      if (hasPending)
                        Text(
                          'Waiting for customer. Checkout is disabled.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade700,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      const SizedBox(height: 24),
                    ],
                  ],
                );
              },
            ),
            const Text(
              'Actual cost',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _costController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: '0.00',
                prefixText: '${currencyModel?.symbol ?? '₱'} ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: isDarkMode(context)
                    ? Color(DARK_CARD_BG_COLOR)
                    : Colors.grey.shade50,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Receipt photo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _isSubmitting
                      ? null
                      : () => _pickReceipt(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(COLOR_PRIMARY),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _isSubmitting
                      ? null
                      : () => _pickReceipt(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                ),
              ],
            ),
            if (_receiptFile != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  _receiptFile!,
                  height: 120,
                  width: 120,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            const SizedBox(height: 32),
            StreamBuilder<List<SubstitutionRequestModel>>(
              stream: PautosService.getSubstitutionRequestsStream(widget.orderId),
              builder: (context, subSnap) {
                final subs = subSnap.data ?? [];
                final hasPending = subs.any((s) => s.status == 'pending');
                return SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (_isSubmitting || hasPending)
                        ? null
                        : _completeCheckout,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.check_circle),
                    label: Text(
                      _isSubmitting
                          ? 'Submitting...'
                          : hasPending
                              ? 'Waiting for customer'
                              : 'Checkout Complete',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(COLOR_ACCENT),
                      foregroundColor: Colors.white,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
