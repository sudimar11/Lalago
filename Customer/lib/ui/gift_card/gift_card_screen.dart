import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/gift_cards_model.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/gift_card_service.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/gift_card/gift_card_history_list_screen.dart';
import 'package:foodie_customer/ui/gift_card/gift_card_purchase_screen.dart';
import 'package:foodie_customer/ui/gift_card/gift_card_redeem_screen.dart';

class GiftCardScreen extends StatefulWidget {
  const GiftCardScreen({super.key});

  @override
  State<GiftCardScreen> createState() => _GiftCardScreenState();
}

class _GiftCardScreenState extends State<GiftCardScreen> {
  List<GiftCardsModel> giftCardList = [];
  GiftCardConfig? config;
  bool isLoading = true;
  String? configError;

  final _pageController = PageController(viewportFraction: 0.90);
  int currentPage = 0;
  final TextEditingController amountController = TextEditingController();
  final TextEditingController messageController = TextEditingController();
  final TextEditingController recipientEmailController = TextEditingController();
  bool isGiftToSomeone = false;

  List<String> get amountOptions {
    if (config == null) return ['1000', '2000', '5000'];
    return config!.denominations.map((e) => e.toString()).toList();
  }

  String selectedAmount = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    recipientEmailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      isLoading = true;
      configError = null;
    });

    try {
      final cfg = await GiftCardService.getConfig();
      List<GiftCardsModel> designs = [];
      try {
        designs = await FireStoreUtils.getGiftCard();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        config = cfg;
        giftCardList = designs;
        if (designs.isNotEmpty) {
          messageController.text = designs[0].message?.toString() ?? '';
        }
        if (config != null && config!.denominations.isNotEmpty) {
          selectedAmount = config!.denominations.first.toString();
        } else {
          selectedAmount = '1000';
        }
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        configError = e.toString();
      });
    }
  }

  void _onContinue() {
    double? amount;
    if (selectedAmount == 'Custom') {
      final v = double.tryParse(amountController.text.trim());
      if (v == null || v <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid amount'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      if (config != null) {
        if (v < config!.customAmountMin || v > config!.customAmountMax) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Amount must be between ${config!.customAmountMin} '
                'and ${config!.customAmountMax}',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
      amount = v;
    } else {
      amount = double.tryParse(selectedAmount);
    }

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select or enter an amount'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (config != null && !config!.enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gift cards are currently disabled'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    String? recipientEmail;
    if (isGiftToSomeone && (config?.allowGiftPurchase ?? true)) {
      final email = recipientEmailController.text.trim();
      if (email.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter recipient email for gift'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      if (!RegExp(r'^[\w\-\.]+@[\w\-\.]+\.\w+$').hasMatch(email)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter a valid email address'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      recipientEmail = email;
    }

    push(
      context,
      GiftCardPurchaseScreen(
        giftCardModel:
            giftCardList.isNotEmpty ? giftCardList[currentPage] : null,
        price: amount.toStringAsFixed(0),
        msg: messageController.text.trim(),
        recipientEmail: recipientEmail,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? Colors.grey.shade900 : Colors.grey.shade100,
      appBar: AppBar(
        title: Text(
          'Customize Gift Card',
          style: TextStyle(
            color: Color(COLOR_PRIMARY),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        actions: [
          InkWell(
            onTap: () => push(context, GiftCardHistoryListScreen()),
            child: const Icon(Icons.history),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: () => push(context, GiftCardRedeemScreen()),
            child: const Icon(Icons.redeem),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : configError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(
                          'Could not load gift card settings',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isDarkMode(context)
                                ? Colors.grey.shade300
                                : Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        if (giftCardList.isNotEmpty) ...[
                          SizedBox(
                            height: 200,
                            child: PageView.builder(
                              padEnds: false,
                              itemCount: giftCardList.length,
                              scrollDirection: Axis.horizontal,
                              controller: _pageController,
                              onPageChanged: (value) {
                                setState(() {
                                  currentPage = value;
                                  messageController.text =
                                      giftCardList[value].message?.toString() ??
                                          '';
                                });
                              },
                              itemBuilder: (context, index) {
                                final m = giftCardList[index];
                                return Container(
                                  margin: const EdgeInsets.only(right: 15),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(15),
                                    border:
                                        Border.all(color: Colors.white, width: 5),
                                    image: DecorationImage(
                                      fit: BoxFit.cover,
                                      image: NetworkImage(m.image ?? ''),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              'Swap to choose card',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ] else
                          Container(
                            height: 120,
                            margin: const EdgeInsets.only(top: 16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(15),
                              color: Color(COLOR_PRIMARY).withOpacity(0.15),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.card_giftcard,
                                size: 64,
                                color: Color(COLOR_PRIMARY),
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                ),
                                child: Text(
                                  'Choose amount'.toUpperCase(),
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
                          decoration: BoxDecoration(
                            color: isDarkMode(context)
                                ? Color(DarkContainerColor)
                                : Colors.white,
                            borderRadius:
                                const BorderRadius.all(Radius.circular(10)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 18,
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Gift Card amount',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: isDarkMode(context)
                                              ? Colors.white
                                              : Colors.black,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      selectedAmount == 'Custom'
                                          ? ''
                                          : amountShow(amount: selectedAmount),
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: isDarkMode(context)
                                            ? Colors.white
                                            : Colors.black,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                selectedAmount == 'Custom'
                                    ? Row(
                                        children: [
                                          InkWell(
                                            onTap: () {
                                              setState(() {
                                                selectedAmount = amountOptions
                                                    .isNotEmpty
                                                    ? amountOptions.first
                                                    : '1000';
                                              });
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.all(5),
                                              child: Container(
                                                height: 60,
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                  border: Border.all(
                                                    color: Color(COLOR_PRIMARY),
                                                  ),
                                                ),
                                                child: const Padding(
                                                  padding:
                                                      EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                  ),
                                                  child: Center(
                                                    child: Text('Custom'),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Text(
                                            currencyModel!.symbol.toString(),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: TextField(
                                              controller: amountController,
                                              keyboardType:
                                                  TextInputType.number,
                                              decoration: const InputDecoration(
                                                hintText: 'Amount',
                                              ),
                                            ),
                                          ),
                                          InkWell(
                                            onTap: () {
                                              setState(() {
                                                if (amountController
                                                    .text.isNotEmpty) {
                                                  selectedAmount =
                                                      amountController.text;
                                                }
                                              });
                                            },
                                            child: Text(
                                              'Add',
                                              style: TextStyle(
                                                color: Color(COLOR_PRIMARY),
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : SizedBox(
                                        height: 60,
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: [
                                              ...amountOptions.map((a) {
                                                return InkWell(
                                                  onTap: () {
                                                    setState(() {
                                                      selectedAmount = a;
                                                    });
                                                  },
                                                  child: Padding(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 5,
                                                    ),
                                                    child: Container(
                                                      decoration:
                                                          BoxDecoration(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(14),
                                                        border: Border.all(
                                                          color:
                                                              selectedAmount == a
                                                                  ? Color(
                                                                      COLOR_PRIMARY,
                                                                    )
                                                                  : Colors.grey,
                                                        ),
                                                      ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 10,
                                                        ),
                                                        child: Center(
                                                          child: Text(
                                                            amountShow(
                                                              amount: a,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }),
                                              if (config?.allowCustomAmount ??
                                                  true)
                                                InkWell(
                                                  onTap: () {
                                                    setState(() {
                                                      selectedAmount =
                                                          'Custom';
                                                    });
                                                  },
                                                  child: Padding(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 5,
                                                    ),
                                                    child: Container(
                                                      decoration:
                                                          BoxDecoration(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(14),
                                                        border: Border.all(
                                                          color:
                                                              selectedAmount ==
                                                                      'Custom'
                                                                  ? Color(
                                                                      COLOR_PRIMARY,
                                                                    )
                                                                  : Colors.grey,
                                                        ),
                                                      ),
                                                      child: const Padding(
                                                        padding:
                                                            EdgeInsets
                                                                .symmetric(
                                                          horizontal: 8,
                                                        ),
                                                        child: Center(
                                                          child: Text(
                                                            'Custom',
                                                          ),
                                                        ),
                                                      ),
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
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                ),
                                child: Text(
                                  'Add Message (Optional)'.toUpperCase(),
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
                          decoration: BoxDecoration(
                            color: isDarkMode(context)
                                ? Color(DarkContainerColor)
                                : Colors.white,
                            borderRadius:
                                const BorderRadius.all(Radius.circular(10)),
                          ),
                          child: TextField(
                            controller: messageController,
                            keyboardType: TextInputType.text,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              hintText: 'Enter Message',
                            ),
                          ),
                        ),
                        if (config?.allowGiftPurchase ?? true) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: CheckboxListTile(
                              title: Text(
                                'Gift to someone',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: isDarkMode(context)
                                      ? Colors.grey.shade300
                                      : Colors.grey.shade800,
                                ),
                              ),
                              value: isGiftToSomeone,
                              onChanged: (v) {
                                setState(() {
                                  isGiftToSomeone = v ?? false;
                                  if (!isGiftToSomeone) {
                                    recipientEmailController.clear();
                                  }
                                });
                              },
                              activeColor: Color(COLOR_PRIMARY),
                            ),
                          ),
                          if (isGiftToSomeone)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: TextField(
                                controller: recipientEmailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: InputDecoration(
                                  hintText: 'Recipient email',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
      bottomNavigationBar: isLoading || configError != null
          ? null
          : Padding(
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
                    padding: const EdgeInsets.only(top: 12, bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25.0),
                      side: BorderSide(color: Color(COLOR_PRIMARY)),
                    ),
                  ),
                  child: Text(
                    'Continue',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode(context)
                          ? Colors.black
                          : Colors.white,
                    ),
                  ),
                  onPressed: _onContinue,
                ),
              ),
            ),
    );
  }
}
