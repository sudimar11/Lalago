import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/PautosOrderModel.dart';
import 'package:foodie_customer/model/Ratingmodel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/userPrefrence.dart';

class PautosPostCompletionDialog extends StatefulWidget {
  final PautosOrderModel order;

  const PautosPostCompletionDialog({Key? key, required this.order})
      : super(key: key);

  static Future<void> show(
    BuildContext context,
    PautosOrderModel order,
  ) async {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return PautosPostCompletionDialog(order: order);
      },
    );
  }

  @override
  State<PautosPostCompletionDialog> createState() =>
      _PautosPostCompletionDialogState();
}

class _PautosPostCompletionDialogState extends State<PautosPostCompletionDialog> {
  double _rating = 0;
  bool _hasRated = false;

  void _dismiss() {
    if (MyAppState.currentUser != null) {
      UserPreference.markCompletionDialogShown(
        MyAppState.currentUser!.userID,
        widget.order.id,
      );
    }
    Navigator.of(context).pop();
  }

  Future<void> _rateRider() async {
    final driverId = widget.order.driverID;
    if (driverId == null || driverId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No rider to rate'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_rating <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a rating'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final ref = FirebaseFirestore.instance.collection(Order_Rating).doc();
    final rate = RatingModel(
      id: ref.id,
      orderId: widget.order.id,
      driverId: driverId,
      customerId: MyAppState.currentUser?.userID ?? '',
      vendorId: '',
      productId: '',
      rating: _rating,
      comment: '',
      uname: '${MyAppState.currentUser?.firstName ?? ''} '
          '${MyAppState.currentUser?.lastName ?? ''}'.trim(),
      profile: MyAppState.currentUser?.profilePictureURL ?? '',
      createdAt: Timestamp.now(),
      reviewType: 'rider',
      status: 'approved',
    );

    final err = await FireStoreUtils.firebaseCreateNewReview(rate);
    if (!mounted) return;
    if (err == null) {
      setState(() => _hasRated = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thanks for your rating'),
          backgroundColor: Colors.green,
        ),
      );
      _dismiss();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit rating: $err'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasDriver =
        widget.order.driverID != null && widget.order.driverID!.isNotEmpty;

    return AlertDialog(
      title: const Text('PAUTOS Order Completed'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Your order has been delivered.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
            ),
            if (hasDriver) ...[
              const SizedBox(height: 16),
              const Text(
                'Rate your rider',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              RatingBar.builder(
                initialRating: _rating,
                minRating: 0.5,
                direction: Axis.horizontal,
                allowHalfRating: true,
                itemCount: 5,
                itemPadding: const EdgeInsets.symmetric(horizontal: 4),
                itemBuilder: (context, _) => Icon(
                  Icons.star,
                  color: Color(COLOR_PRIMARY),
                ),
                onRatingUpdate: (r) => setState(() => _rating = r),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _dismiss,
          child: const Text('Later'),
        ),
        if (hasDriver)
          ElevatedButton(
            onPressed: _hasRated ? null : _rateRider,
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(COLOR_PRIMARY),
              foregroundColor: Colors.white,
            ),
            child: const Text('Submit Rating'),
          )
        else
          ElevatedButton(
            onPressed: _dismiss,
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(COLOR_PRIMARY),
              foregroundColor: Colors.white,
            ),
            child: const Text('OK'),
          ),
      ],
    );
  }
}
