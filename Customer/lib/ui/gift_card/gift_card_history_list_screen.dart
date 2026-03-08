import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/gift_cards_order_model.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/gift_card_service.dart';
import 'package:foodie_customer/services/helper.dart';

class GiftCardHistoryListScreen extends StatefulWidget {
  const GiftCardHistoryListScreen({super.key});

  @override
  State<GiftCardHistoryListScreen> createState() =>
      _GiftCardHistoryListScreenState();
}

class _GiftCardHistoryListScreenState extends State<GiftCardHistoryListScreen> {
  List<GiftCardsOrderModel> legacyList = [];
  List<Map<String, dynamic>> newList = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => isLoading = true);
    try {
      final legacy = await FireStoreUtils().getGiftHistory();
      List<Map<String, dynamic>> newCards = [];
      if (MyAppState.currentUser != null) {
        newCards = await GiftCardService.getUserGiftCards(
          MyAppState.currentUser!.userID,
        );
      }
      if (!mounted) return;
      setState(() {
        legacyList = legacy;
        newList = newCards;
        isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? Colors.grey.shade900 : Colors.grey.shade100,
      appBar: AppBar(
        title: Text(
          'Gift Card History',
          style: TextStyle(
            color: Color(COLOR_PRIMARY),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : legacyList.isEmpty && newList.isEmpty
              ? const Center(child: Text('No gift cards found'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      ...newList.map((card) => _buildNewCard(card)),
                      ...legacyList.map((card) => _buildLegacyCard(card)),
                    ],
                  ),
                ),
    );
  }

  Widget _buildNewCard(Map<String, dynamic> card) {
    final code = card['code'] as String? ?? '';
    final balance = (card['remainingBalance'] as num?)?.toDouble() ?? 0;
    final original = (card['originalAmount'] as num?)?.toDouble() ?? 0;
    final status = card['status'] as String? ?? 'active';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: isDarkMode(context) ? Color(DarkContainerColor) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      code,
                      style: TextStyle(
                        fontSize: 16,
                        color: isDarkMode(context)
                            ? Colors.white
                            : Colors.black,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: status == 'active'
                          ? Colors.green.withOpacity(0.2)
                          : Colors.grey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        color: status == 'active' ? Colors.green : Colors.grey,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Balance: ${amountShow(amount: balance.toString())}',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkMode(context)
                          ? Colors.grey.shade400
                          : Colors.grey.shade700,
                    ),
                  ),
                  Text(
                    amountShow(amount: original.toString()),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDarkMode(context)
                          ? Colors.white
                          : Colors.black,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegacyCard(GiftCardsOrderModel card) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: isDarkMode(context) ? Color(DarkContainerColor) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      card.giftTitle ?? 'Gift Card',
                      style: TextStyle(
                        fontSize: 16,
                        color: isDarkMode(context)
                            ? Colors.white
                            : Colors.black,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'LEGACY',
                      style: TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    card.redeem == true ? 'Redeemed' : 'Active',
                    style: TextStyle(
                      color: card.redeem == true ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    'Gift code'.toUpperCase(),
                    style: TextStyle(
                      color: isDarkMode(context)
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (card.giftCode ?? '')
                          .replaceAllMapped(
                            RegExp(r'.{4}'),
                            (m) => '${m.group(0)} ',
                          )
                          .trim(),
                      style: TextStyle(
                        color: isDarkMode(context)
                            ? Colors.white
                            : Colors.black,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    amountShow(amount: card.price ?? '0'),
                    style: TextStyle(
                      color: isDarkMode(context)
                          ? Colors.white
                          : Colors.black,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
