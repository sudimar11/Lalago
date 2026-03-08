import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/gift_cards_order_model.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/gift_card_service.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/container/ContainerScreen.dart';
import 'package:foodie_customer/ui/wallet/walletScreen.dart';

class GiftCardRedeemScreen extends StatefulWidget {
  const GiftCardRedeemScreen({super.key});

  @override
  State<GiftCardRedeemScreen> createState() => _GiftCardRedeemScreenState();
}

class _GiftCardRedeemScreenState extends State<GiftCardRedeemScreen> {
  final TextEditingController giftCodeController = TextEditingController();
  final TextEditingController giftPinController = TextEditingController();

  Future<void> _redeem() async {
    final code = giftCodeController.text.trim().replaceAll(' ', '').toUpperCase();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter gift card code'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (MyAppState.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to redeem'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await showProgress(context, 'Please wait...', false);

    try {
      final validation =
          await GiftCardService.validateGiftCard(code);
      final valid = validation['valid'] == true;
      final needsClaim = validation['needsClaim'] == true;

      if (valid) {
        String? cardId = validation['cardId'] as String?;
        double remainingBalance =
            (validation['remainingBalance'] as num?)?.toDouble() ?? 0.0;

        if (needsClaim) {
          try {
            final claimResult = await GiftCardService.claimGiftCard(code);
            cardId = claimResult['cardId'] as String?;
            remainingBalance =
                (claimResult['remainingBalance'] as num?)?.toDouble() ?? 0.0;
          } catch (e) {
            hideProgress();
            final msg = e.toString();
            if (msg.contains('different email')) {
              _showError('This gift was sent to a different email address');
            } else {
              _showError(msg.replaceFirst('Exception: ', ''));
            }
            return;
          }
        }

        if (cardId == null || remainingBalance <= 0) {
          hideProgress();
          _showError('Invalid gift card');
          return;
        }

        await GiftCardService.redeemGiftCard(
          cardId: cardId,
          amount: remainingBalance,
          userId: MyAppState.currentUser!.userID,
          orderId: null,
        );

        final paymentId = await FireStoreUtils.createPaymentId();
        await FireStoreUtils.topUpWalletAmount(
          paymentMethod: 'Gift Card',
          amount: remainingBalance,
          id: paymentId,
        );
        await FireStoreUtils.updateWalletAmount(amount: remainingBalance);
        await FireStoreUtils.sendTopUpMail(
          paymentMethod: 'Gift Card',
          amount: remainingBalance.toString(),
          tractionId: paymentId,
        );

        hideProgress();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gift card redeemed successfully'),
            backgroundColor: Colors.green,
          ),
        );
        pushAndRemoveUntil(
          context,
          ContainerScreen(
            user: MyAppState.currentUser!,
            currentWidget: WalletScreen(),
            appBarTitle: 'Wallet',
          ),
          false,
        );
        return;
      }

      final legacyCode = giftCodeController.text.replaceAll(' ', '');
      if (legacyCode.length == 16 &&
          RegExp(r'^\d+$').hasMatch(legacyCode) &&
          giftPinController.text.isNotEmpty) {
        final value =
            await FireStoreUtils().checkRedeemCode(legacyCode);
        if (value != null) {
          final giftCodeModel = value;
          if (giftCodeModel.redeem == true) {
            hideProgress();
            _showError('Gift voucher already redeemed');
            return;
          }
          if (giftCodeModel.giftPin != giftPinController.text) {
            hideProgress();
            _showError('Invalid gift PIN');
            return;
          }
          if (giftCodeModel.expireDate != null &&
              giftCodeModel.expireDate!.toDate().isBefore(DateTime.now())) {
            hideProgress();
            _showError('Gift voucher expired');
            return;
          }

          giftCodeModel.redeem = true;
          final amount =
              double.tryParse(giftCodeModel.price ?? '0') ?? 0.0;

          final paymentId = await FireStoreUtils.createPaymentId();
          await FireStoreUtils.topUpWalletAmount(
            paymentMethod: 'Gift Voucher (Legacy)',
            amount: amount,
            id: paymentId,
          );
          await FireStoreUtils.updateWalletAmount(amount: amount);
          await FireStoreUtils.sendTopUpMail(
            paymentMethod: 'Gift Voucher (Legacy)',
            amount: giftCodeModel.price ?? '0',
            tractionId: paymentId,
          );
          await FireStoreUtils().placeGiftCardOrder(giftCodeModel);

          hideProgress();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Legacy gift card redeemed. New cards use code-only format.',
              ),
              backgroundColor: Colors.green,
            ),
          );
          pushAndRemoveUntil(
            context,
            ContainerScreen(
              user: MyAppState.currentUser!,
              currentWidget: WalletScreen(),
              appBarTitle: 'Wallet',
            ),
            false,
          );
          return;
        }
      }

      hideProgress();
      _showError(
        validation['error'] as String? ??
            'Invalid gift card code. For legacy cards, enter 16-digit code and PIN.',
      );
    } catch (e) {
      hideProgress();
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? Colors.grey.shade900 : Colors.grey.shade100,
      appBar: AppBar(
        title: Text(
          'Redeem Gift Card',
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
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDarkMode(context)
                  ? const Color(DarkContainerBorderColor)
                  : Colors.grey.shade100,
              width: 1,
            ),
            color: isDarkMode(context)
                ? const Color(DarkContainerColor)
                : Colors.white,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Gift Card Code (LALA-XXXX or 16-digit)',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDarkMode(context)
                        ? Colors.grey.shade300
                        : Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: giftCodeController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 25,
                  decoration: InputDecoration(
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                    ),
                    hintText: 'e.g. LALA-A1B2C3D4E5F6',
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: Color(COLOR_PRIMARY),
                        width: 2,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'PIN (legacy cards only)',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDarkMode(context)
                        ? Colors.grey.shade400
                        : Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: giftPinController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                    ),
                    hintText: '6-digit PIN for old cards',
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: Color(COLOR_PRIMARY),
                        width: 2,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(COLOR_PRIMARY),
            padding: const EdgeInsets.symmetric(horizontal: 90, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
              side: BorderSide(color: Color(COLOR_PRIMARY)),
            ),
          ),
          child: Text(
            'Redeem',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDarkMode(context) ? Colors.black : Colors.white,
            ),
          ),
          onPressed: _redeem,
        ),
      ),
    );
  }
}
