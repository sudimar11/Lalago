import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:brgy/widgets/orders/ai_sms_status.dart';

/// Widget that displays order information including customer details,
/// products, and SMS sender widgets
class OrderInfoSection extends StatefulWidget {
  final Map<String, dynamic> data;
  final String status;
  const OrderInfoSection({super.key, required this.data, required this.status});

  @override
  State<OrderInfoSection> createState() => _OrderInfoSectionState();
}

class _OrderInfoSectionState extends State<OrderInfoSection> {
  // Helper method to fetch customer phone number (for display purposes)
  Future<String> _fetchCustomerPhone(String customerId) async {
    try {
      final customerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(customerId)
          .get();

      if (customerDoc.exists) {
        final customerData = customerDoc.data();
        return (customerData?['phoneNumber'] ?? '').toString();
      }
      return '';
    } catch (e) {
      print('Error fetching customer phone: $e');
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Extract customer info
    final author = widget.data['author'] as Map<String, dynamic>?;
    final customerName = author != null
        ? '${author['firstName'] ?? ''} ${author['lastName'] ?? ''}'.trim()
        : 'Unknown Customer';
    final customerId = author?['id'] as String? ?? '';

    // Extract phone info
    final takeAway = widget.data['takeAway'] as bool? ?? false;

    // Extract products
    final products = widget.data['products'] as List<dynamic>? ?? [];
    final productsCount = products.length;

    // Get first product image
    String? productImage;
    if (products.isNotEmpty && products.first is Map) {
      productImage =
          (products.first as Map<String, dynamic>)['photo'] as String?;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Customer & Product Image
        Row(
          children: [
            // Product image
            if (productImage != null && productImage.isNotEmpty)
              Container(
                width: 60,
                height: 60,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  image: DecorationImage(
                    image: NetworkImage(productImage),
                    fit: BoxFit.cover,
                  ),
                ),
              )
            else
              Container(
                width: 60,
                height: 60,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade300,
                ),
                child: const Icon(Icons.fastfood, color: Colors.grey),
              ),

            // Customer info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customerName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // Show customer phone number below name
                  if (customerId.isNotEmpty && !takeAway) ...[
                    const SizedBox(height: 2),
                    FutureBuilder<String>(
                      future: _fetchCustomerPhone(customerId),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Text(
                            'Loading phone...',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                              fontStyle: FontStyle.italic,
                            ),
                          );
                        }
                        if (snapshot.hasError || !snapshot.hasData) {
                          return Text(
                            'No phone available',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                              fontStyle: FontStyle.italic,
                            ),
                          );
                        }
                        final phone = snapshot.data!;
                        if (phone.isEmpty) {
                          return Text(
                            'No phone available',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                              fontStyle: FontStyle.italic,
                            ),
                          );
                        }
                        return Text(
                          phone,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        );
                      },
                    ),
                  ],
                  // Show "Waiting for restaurants" text for Order Placed status
                  if (widget.status == 'Order Placed') ...[
                    const SizedBox(height: 4),
                    Text(
                      'Waiting for restaurants',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Circular progress indicator on the right for "Order Placed" status
            if (widget.status == 'Order Placed')
              Container(
                margin: const EdgeInsets.only(left: 12),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.orange.shade600,
                    ),
                  ),
                ),
              ),
          ],
        ),

        const SizedBox(height: 12),

        // AI SMS status (replaces manual SMS UI)
        AISMSStatus(
          status: widget.status,
          orderData: widget.data,
        ),

        const SizedBox(height: 12),

        // Products summary
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.shopping_cart,
                      size: 16, color: Colors.grey.shade700),
                  const SizedBox(width: 6),
                  Text(
                    '$productsCount ${productsCount == 1 ? 'Item' : 'Items'}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const Spacer(),
                  if (widget.data['paymentMethod'] != null)
                    PaymentMethodChip(
                        method: widget.data['paymentMethod'] as String),
                ],
              ),
              if (products.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...products.map((product) {
                  if (product is! Map<String, dynamic>)
                    return const SizedBox.shrink();
                  final name = product['name'] as String? ?? 'Unknown';
                  final qty = product['quantity'] ?? 1;
                  final price = product['price'] as String? ?? '0';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Text(
                          '${qty}x ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '₱$price',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),

        // Notes if any
        if (widget.data['notes'] != null &&
            (widget.data['notes'] as String).isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.note, size: 16, color: Colors.amber.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.data['notes'] as String,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Widget that displays payment method chip
class PaymentMethodChip extends StatelessWidget {
  final String method;
  const PaymentMethodChip({super.key, required this.method});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            method.toLowerCase().contains('cash')
                ? Icons.money
                : Icons.credit_card,
            size: 12,
            color: Colors.green.shade700,
          ),
          const SizedBox(width: 4),
          Text(
            method,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
  }
}
