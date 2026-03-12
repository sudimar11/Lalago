import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/AddressModel.dart';
import 'package:foodie_customer/model/PautosOrderModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/deliveryAddressScreen/DeliveryAddressScreen.dart';
import 'package:foodie_customer/ui/login/LoginScreen.dart';
import 'package:foodie_customer/ui/pautos/pautos_order_detail_screen.dart';

class CreatePautosRequestScreen extends StatefulWidget {
  const CreatePautosRequestScreen({Key? key}) : super(key: key);

  @override
  State<CreatePautosRequestScreen> createState() =>
      _CreatePautosRequestScreenState();
}

class _CreatePautosRequestScreenState extends State<CreatePautosRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _shoppingListController = TextEditingController();
  final _budgetController = TextEditingController();
  final _preferredStoreController = TextEditingController();

  AddressModel? _selectedAddress;
  bool _isSubmitting = false;
  String _paymentMethod = 'COD';

  @override
  void initState() {
    super.initState();
    _selectedAddress = MyAppState.selectedPosition;
  }

  @override
  void dispose() {
    _shoppingListController.dispose();
    _budgetController.dispose();
    _preferredStoreController.dispose();
    super.dispose();
  }

  Future<void> _selectAddress() async {
    final result = await Navigator.of(context).push<AddressModel>(
      MaterialPageRoute(
        builder: (context) => const DeliveryAddressScreen(),
      ),
    );
    if (result != null && mounted) {
      setState(() => _selectedAddress = result);
    }
  }

  Future<void> _submit() async {
    if (MyAppState.currentUser == null) {
      push(context, LoginScreen());
      return;
    }
    if (_selectedAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a delivery address'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);
    showProgress(context, 'Creating PAUTOS request...', false);

    try {
      final budget = double.tryParse(_budgetController.text.trim()) ?? 0;
      final order = PautosOrderModel(
        id: '',
        authorID: MyAppState.currentUser!.userID,
        shoppingList: _shoppingListController.text.trim(),
        maxBudget: budget,
        preferredStore: _preferredStoreController.text.trim().isNotEmpty
            ? _preferredStoreController.text.trim()
            : null,
        address: _selectedAddress!,
        status: 'Request Posted',
        createdAt: Timestamp.now(),
        paymentMethod: _paymentMethod,
      );

      final orderId =
          await FireStoreUtils().createPautosOrder(order);
      if (!mounted) return;
      await hideProgress();
      setState(() => _isSubmitting = false);

      pushReplacement(
        context,
        PautosOrderDetailScreen(orderId: orderId),
      );
    } catch (e) {
      if (mounted) {
        await hideProgress();
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Create PAUTOS Request',
          style: TextStyle(fontFamily: 'Poppinsm'),
        ),
        backgroundColor: Color(COLOR_PRIMARY),
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _shoppingListController,
                decoration: const InputDecoration(
                  labelText: 'Shopping List',
                  hintText: 'e.g. 2kg rice, cooking oil, shampoo',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Enter what you need';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _budgetController,
                decoration: const InputDecoration(
                  labelText: 'Max Budget',
                  hintText: 'e.g. 500',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Enter max budget';
                  }
                  final n = double.tryParse(v.trim());
                  if (n == null || n <= 0) {
                    return 'Enter a valid positive amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _preferredStoreController,
                decoration: const InputDecoration(
                  labelText: 'Preferred Store (optional)',
                  hintText: 'e.g. Indomaret near me',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              const Text(
                'Payment Method',
                style: TextStyle(
                  fontFamily: 'Poppinsm',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Cash on Delivery'),
                      selected: _paymentMethod == 'COD',
                      onSelected: (v) {
                        if (v) setState(() => _paymentMethod = 'COD');
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Wallet'),
                      selected: _paymentMethod == 'Wallet',
                      onSelected: (v) {
                        if (v) setState(() => _paymentMethod = 'Wallet');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Delivery Address',
                style: TextStyle(
                  fontFamily: 'Poppinsm',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _selectAddress,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.grey.shade400,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        color: Color(COLOR_PRIMARY),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedAddress != null
                              ? _selectedAddress!.getFullAddress()
                              : 'Tap to select address',
                          style: TextStyle(
                            fontFamily: 'Poppinsr',
                            color: _selectedAddress != null
                                ? (isDarkMode(context)
                                    ? Colors.white
                                    : Colors.black87)
                                : Colors.grey,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(COLOR_PRIMARY),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Submit Request',
                        style: TextStyle(
                          fontFamily: 'Poppinsm',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
