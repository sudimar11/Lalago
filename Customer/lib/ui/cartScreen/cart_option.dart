import 'package:flutter/material.dart';
import 'package:foodie_customer/services/localDatabase.dart'; // Import your CartProduct model

class CartOptionsSheet extends StatelessWidget {
  final CartProduct cartProduct;

  const CartOptionsSheet({Key? key, required this.cartProduct})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Modify ${cartProduct.name}",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          // Update Quantity Button
          ElevatedButton(
            onPressed: () {
              // You can add logic to modify quantity here
              Navigator.pop(context, true); // Signals cart update
            },
            child: Text("Update Quantity"),
          ),

          // Remove from Cart Button
          ElevatedButton(
            onPressed: () {
              // You can add logic to remove item from cart here
              Navigator.pop(context, true); // Signals cart update
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text("Remove from Cart"),
          ),

          // Cancel Button
          TextButton(
            onPressed: () =>
                Navigator.pop(context, false), // Cancels without changes
            child: Text("Cancel"),
          ),
        ],
      ),
    );
  }
}
