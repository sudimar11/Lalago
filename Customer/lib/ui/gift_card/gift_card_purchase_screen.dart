import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/gift_cards_model.dart';
import 'package:foodie_customer/services/gift_card_service.dart';
import 'package:foodie_customer/services/helper.dart';

class GiftCardPurchaseScreen extends StatefulWidget {
  final GiftCardsModel? giftCardModel;
  final String price;
  final String msg;
  final String? recipientEmail;

  const GiftCardPurchaseScreen({
    super.key,
    this.giftCardModel,
    required this.price,
    required this.msg,
    this.recipientEmail,
  });

  @override
  State<GiftCardPurchaseScreen> createState() => _GiftCardPurchaseScreenState();
}

class _GiftCardPurchaseScreenState extends State<GiftCardPurchaseScreen> {
  bool _isLoading = false;
  String? _error;

  Future<void> _createGiftCard() async {
    if (_isLoading) return;
    final amount = double.tryParse(widget.price);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Invalid amount');
      return;
    }
    if (MyAppState.currentUser == null) {
      setState(() => _error = 'Please sign in to purchase');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await GiftCardService.createGiftCard(
        amount: amount,
        giftMessage: widget.msg.isEmpty ? null : widget.msg,
        deliveryMethod: widget.recipientEmail != null ? 'email' : 'direct',
        designTemplate: widget.giftCardModel?.title ?? 'celebration',
        recipientEmail: widget.recipientEmail,
      );
      if (!mounted) return;

      final code = result['code'] as String? ?? '';
      final expiresAt = result['expiresAt'] as String? ?? '';

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(
            widget.recipientEmail != null ? 'Gift Card Sent' : 'Gift Card Created',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.recipientEmail != null
                    ? 'Share this code with the recipient. They can claim it in Profile → Gift Cards → Redeem:'
                    : 'Your gift card code (save this):',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SelectableText(
                code,
                style: const TextStyle(
                  fontSize: 18,
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (expiresAt.isNotEmpty)
                Text(
                  'Expires: $expiresAt',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Code copied to clipboard')),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy Code'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: $_error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.giftCardModel;
    final imageUrl = model?.image;
    final expiryDays = model?.expiryDay ?? '365';

    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? Colors.grey.shade900 : Colors.grey.shade100,
      appBar: AppBar(
        title: Text(
          'Complete purchase',
          style: TextStyle(
            color: Color(COLOR_PRIMARY),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              if (imageUrl != null && imageUrl.isNotEmpty)
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white, width: 5),
                    image: DecorationImage(
                      fit: BoxFit.cover,
                      image: NetworkImage(imageUrl),
                    ),
                  ),
                )
              else
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    color: Color(COLOR_PRIMARY).withOpacity(0.2),
                    border: Border.all(color: Colors.white, width: 5),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.card_giftcard,
                      size: 80,
                      color: Color(COLOR_PRIMARY),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: Color(COLOR_PRIMARY).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: Text(
                    'Complete payment and share this e-gift card with '
                    'loved ones using any app.',
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Text(
                        'BILL SUMMARY'.toUpperCase(),
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade100, width: 1),
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.5),
                      blurRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 5,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Subtotal',
                              style: TextStyle(fontFamily: 'Poppinsm')),
                          Text(
                            amountShow(amount: widget.price),
                            style: const TextStyle(
                              fontFamily: 'Poppinsm',
                              color: Color(0xff333333),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(thickness: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 5,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Grand Total',
                              style: TextStyle(fontFamily: 'Poppinsm')),
                          Text(
                            amountShow(amount: widget.price),
                            style: const TextStyle(
                              fontFamily: 'Poppinsm',
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'Gift card expires in $expiryDays days after purchase',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(
          right: 40.0,
          left: 40.0,
          top: 10,
          bottom: 10,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: double.infinity),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(COLOR_PRIMARY),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25.0),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    'Confirm COD Purchase',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode(context) ? Colors.black : Colors.white,
                    ),
                  ),
            onPressed: _isLoading ? null : _createGiftCard,
          ),
        ),
      ),
    );
  }
}
