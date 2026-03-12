import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/model/coupon.dart';
import 'package:brgy/model/coupon_eligibility_rules.dart';
import 'package:brgy/services/coupon_service.dart';
import 'package:intl/intl.dart';

class CouponAddEditPage extends StatefulWidget {
  final Coupon? coupon;
  final Map<String, dynamic>? prefill;

  const CouponAddEditPage({super.key, this.coupon, this.prefill});

  @override
  State<CouponAddEditPage> createState() => _CouponAddEditPageState();
}

class _CouponAddEditPageState extends State<CouponAddEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _titleController = TextEditingController();
  final _shortDescriptionController = TextEditingController();
  final _discountValueController = TextEditingController();
  final _minOrderAmountController = TextEditingController();
  final _minItemsController = TextEditingController();
  final _maxUsagePerUserController = TextEditingController();
  final _globalUsageLimitController = TextEditingController();
  final _minCompletedOrdersController = TextEditingController();
  final _userIdWhitelistController = TextEditingController();
  final _imagePicker = ImagePicker();

  String _discountType = 'fixed_amount';
  Set<String> _selectedUserCategories = {};
  bool _firstTimeUserOnly = false;
  String _priorCouponUsageType = 'none';
  bool _priorCouponUsageAllowed = false;
  DateTime _validFrom = DateTime.now();
  DateTime _validTo = DateTime.now().add(const Duration(days: 30));
  File? _newImage;
  String? _existingImageUrl;
  bool _isUploading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.prefill != null && widget.coupon == null) {
      final p = widget.prefill!;
      _titleController.text = (p['title'] as String?) ?? 'Demand recovery promo';
      _discountType = (p['discountType'] as String?) ?? 'percentage';
      _discountValueController.text = (p['discountValue']?.toString() ?? '20');
      _validTo = (p['validTo'] as DateTime?) ?? DateTime.now().add(const Duration(days: 7));
    } else if (widget.coupon != null) {
      final coupon = widget.coupon!;
      _codeController.text = coupon.code;
      _titleController.text = coupon.title;
      _shortDescriptionController.text = coupon.shortDescription;
      _discountType = coupon.discountType;
      _discountValueController.text = coupon.discountValue.toString();
      _minOrderAmountController.text = coupon.minOrderAmount.toString();
      _minItemsController.text = coupon.minItems?.toString() ?? '1';
      _maxUsagePerUserController.text =
          coupon.maxUsagePerUser?.toString() ?? '';
      _globalUsageLimitController.text =
          coupon.globalUsageLimit?.toString() ?? '';
      _validFrom = coupon.validFrom.toDate();
      _validTo = coupon.validTo.toDate();
      _existingImageUrl = coupon.imageUrl;

      // Initialize eligibility rules if present
      if (coupon.eligibilityRules != null) {
        final rules = coupon.eligibilityRules!;
        _selectedUserCategories = Set<String>.from(
          rules.userCategories ?? [],
        );
        _minCompletedOrdersController.text =
            rules.minCompletedOrders?.toString() ?? '';
        _firstTimeUserOnly = rules.firstTimeUserOnly ?? false;
        if (rules.priorCouponUsage != null) {
          _priorCouponUsageType = rules.priorCouponUsage!.type;
          _priorCouponUsageAllowed = rules.priorCouponUsage!.allowed;
        }
        if (rules.userIds != null && rules.userIds!.isNotEmpty) {
          _userIdWhitelistController.text = rules.userIds!.join(', ');
        }
      }
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _titleController.dispose();
    _shortDescriptionController.dispose();
    _discountValueController.dispose();
    _minOrderAmountController.dispose();
    _minItemsController.dispose();
    _maxUsagePerUserController.dispose();
    _globalUsageLimitController.dispose();
    _minCompletedOrdersController.dispose();
    _userIdWhitelistController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );
      if (image != null) {
        setState(() {
          _newImage = File(image.path);
          _existingImageUrl = null; // Clear existing when new image selected
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  void _removeImage() {
    setState(() {
      _newImage = null;
      _existingImageUrl = null;
    });
  }

  Future<void> _selectDate(bool isFromDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isFromDate ? _validFrom : _validTo,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      setState(() {
        if (isFromDate) {
          _validFrom = picked;
          if (_validTo.isBefore(_validFrom)) {
            _validTo = _validFrom.add(const Duration(days: 30));
          }
        } else {
          _validTo = picked;
        }
      });
    }
  }

  Future<void> _saveCoupon() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_validTo.isBefore(_validFrom) || _validTo.isAtSameMomentAs(_validFrom)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Valid To date must be after Valid From date'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate eligibility rules
    if (_firstTimeUserOnly && _minCompletedOrdersController.text.trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot require minimum orders and first-time users only'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _isUploading = true;
    });

    try {
      String? imageUrl = _existingImageUrl;

      // Upload new image if selected
      if (_newImage != null) {
        imageUrl = await CouponService.uploadCouponImage(_newImage!);
      }

      final discountValue = double.parse(_discountValueController.text.trim());
      final minOrderAmount =
          double.parse(_minOrderAmountController.text.trim());
      final minItems = _minItemsController.text.trim().isEmpty
          ? 1
          : int.tryParse(_minItemsController.text.trim()) ?? 1;
      final maxUsagePerUser = _maxUsagePerUserController.text.trim().isEmpty
          ? null
          : int.tryParse(_maxUsagePerUserController.text.trim());
      final globalUsageLimit =
          _globalUsageLimitController.text.trim().isEmpty
              ? null
              : int.tryParse(_globalUsageLimitController.text.trim());

      if (discountValue <= 0) {
        throw Exception('Discount value must be greater than 0');
      }

      if (_discountType == 'percentage' &&
          (discountValue < 0 || discountValue > 100)) {
        throw Exception('Percentage must be between 0 and 100');
      }

      if (minOrderAmount < 0) {
        throw Exception('Minimum order amount cannot be negative');
      }

      // Build eligibility rules
      CouponEligibilityRules? eligibilityRules;
      if (_selectedUserCategories.isNotEmpty ||
          _minCompletedOrdersController.text.trim().isNotEmpty ||
          _firstTimeUserOnly ||
          _priorCouponUsageType != 'none' ||
          _userIdWhitelistController.text.trim().isNotEmpty) {
        List<String>? userIds;
        if (_userIdWhitelistController.text.trim().isNotEmpty) {
          userIds = _userIdWhitelistController.text
              .split(',')
              .map((id) => id.trim())
              .where((id) => id.isNotEmpty)
              .toList();
        }

        PriorCouponUsage? priorUsage;
        if (_priorCouponUsageType != 'none') {
          priorUsage = PriorCouponUsage(
            type: _priorCouponUsageType,
            allowed: _priorCouponUsageAllowed,
          );
        }

        eligibilityRules = CouponEligibilityRules(
          userCategories: _selectedUserCategories.isNotEmpty
              ? _selectedUserCategories.toList()
              : null,
          minCompletedOrders: _minCompletedOrdersController.text.trim().isNotEmpty
              ? int.tryParse(_minCompletedOrdersController.text.trim())
              : null,
          firstTimeUserOnly: _firstTimeUserOnly ? true : null,
          priorCouponUsage: priorUsage,
          userIds: userIds?.isNotEmpty == true ? userIds : null,
        );

        if (!eligibilityRules.isValid()) {
          throw Exception('Invalid eligibility rules configuration');
        }
      }

      final coupon = Coupon(
        id: widget.coupon?.id ?? '',
        code: _codeController.text.trim().toUpperCase(),
        title: _titleController.text.trim(),
        shortDescription: _shortDescriptionController.text.trim(),
        discountType: _discountType,
        discountValue: discountValue,
        minOrderAmount: minOrderAmount,
        minItems: minItems,
        validFrom: Timestamp.fromDate(_validFrom),
        validTo: Timestamp.fromDate(_validTo),
        maxUsagePerUser: maxUsagePerUser,
        globalUsageLimit: globalUsageLimit,
        imageUrl: imageUrl,
        isEnabled: widget.coupon?.isEnabled ?? true,
        isDeleted: false,
        createdAt: widget.coupon?.createdAt ?? Timestamp.now(),
        updatedAt: Timestamp.now(),
        eligibilityRules: eligibilityRules,
      );

      if (widget.coupon == null) {
        await CouponService.createCoupon(coupon);
      } else {
        await CouponService.updateCoupon(coupon);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.coupon == null
                  ? 'Coupon created successfully'
                  : 'Coupon updated successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving coupon: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy');
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.coupon == null ? 'Create Coupon' : 'Edit Coupon'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveCoupon,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Coupon Code
              TextFormField(
                controller: _codeController,
                decoration: const InputDecoration(
                  labelText: 'Coupon Code *',
                  hintText: 'e.g., SAVE20',
                  prefixIcon: Icon(Icons.tag),
                  helperText: 'Unique code for customers to enter',
                ),
                textCapitalization: TextCapitalization.characters,
                enabled: widget.coupon == null, // Can't change code when editing
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a coupon code';
                  }
                  if (value.trim().length < 3) {
                    return 'Coupon code must be at least 3 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Title
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Coupon Title *',
                  hintText: 'e.g., Summer Sale',
                  prefixIcon: Icon(Icons.title),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Short Description
              TextFormField(
                controller: _shortDescriptionController,
                decoration: const InputDecoration(
                  labelText: 'Short Description *',
                  hintText: 'Brief description of the coupon offer',
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a description';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Discount Type
              DropdownButtonFormField<String>(
                value: _discountType,
                decoration: const InputDecoration(
                  labelText: 'Discount Type *',
                  prefixIcon: Icon(Icons.category),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'fixed_amount',
                    child: Text('Fixed Amount'),
                  ),
                  DropdownMenuItem(
                    value: 'percentage',
                    child: Text('Percentage'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _discountType = value!;
                  });
                },
              ),
              const SizedBox(height: 16),
              // Discount Value
              TextFormField(
                controller: _discountValueController,
                decoration: InputDecoration(
                  labelText: _discountType == 'percentage'
                      ? 'Discount Percentage (%) *'
                      : 'Discount Amount (₱) *',
                  hintText: _discountType == 'percentage' ? 'e.g., 10' : 'e.g., 50.00',
                  prefixIcon: const Icon(Icons.attach_money),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a discount value';
                  }
                  final numValue = double.tryParse(value.trim());
                  if (numValue == null || numValue <= 0) {
                    return 'Please enter a valid positive number';
                  }
                  if (_discountType == 'percentage' &&
                      (numValue < 0 || numValue > 100)) {
                    return 'Percentage must be between 0 and 100';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Minimum Order Amount
              TextFormField(
                controller: _minOrderAmountController,
                decoration: const InputDecoration(
                  labelText: 'Minimum Order Amount (₱) *',
                  hintText: '0.00',
                  prefixIcon: Icon(Icons.shopping_cart),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter minimum order amount';
                  }
                  final numValue = double.tryParse(value.trim());
                  if (numValue == null || numValue < 0) {
                    return 'Please enter a valid non-negative number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Minimum Items
              TextFormField(
                controller: _minItemsController,
                decoration: const InputDecoration(
                  labelText: 'Minimum Items *',
                  hintText: 'e.g., 1, 2, 3',
                  prefixIcon: Icon(Icons.shopping_bag),
                  helperText: 'Minimum number of items required (default: 1)',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter minimum items (default: 1)';
                  }
                  final intValue = int.tryParse(value.trim());
                  if (intValue == null || intValue < 1) {
                    return 'Please enter a valid positive integer (≥ 1)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Valid From Date
              InkWell(
                onTap: () => _selectDate(true),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Valid From *',
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    dateFormat.format(_validFrom),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Valid To Date
              InkWell(
                onTap: () => _selectDate(false),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Valid To *',
                    prefixIcon: Icon(Icons.event),
                  ),
                  child: Text(
                    dateFormat.format(_validTo),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Max Usage Per User
              TextFormField(
                controller: _maxUsagePerUserController,
                decoration: const InputDecoration(
                  labelText: 'Max Usage Per User (Optional)',
                  hintText: 'Leave empty for unlimited',
                  prefixIcon: Icon(Icons.person),
                  helperText: 'Maximum times a single user can use this coupon',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    final numValue = int.tryParse(value.trim());
                    if (numValue == null || numValue < 1) {
                      return 'Please enter a valid positive number';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              // User Eligibility Rules Section
              const Divider(thickness: 2),
              const SizedBox(height: 16),
              const Text(
                'User Eligibility Rules (Optional)',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Define who can view and use this coupon',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 16),
              // User Categories
              const Text(
                'User Categories',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('New User'),
                    selected: _selectedUserCategories.contains('new_user'),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedUserCategories.add('new_user');
                        } else {
                          _selectedUserCategories.remove('new_user');
                        }
                      });
                    },
                  ),
                  FilterChip(
                    label: const Text('Regular Customer'),
                    selected: _selectedUserCategories.contains('regular_customer'),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedUserCategories.add('regular_customer');
                        } else {
                          _selectedUserCategories.remove('regular_customer');
                        }
                      });
                    },
                  ),
                  FilterChip(
                    label: const Text('VIP'),
                    selected: _selectedUserCategories.contains('vip'),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedUserCategories.add('vip');
                        } else {
                          _selectedUserCategories.remove('vip');
                        }
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Minimum Completed Orders
              TextFormField(
                controller: _minCompletedOrdersController,
                decoration: const InputDecoration(
                  labelText: 'Minimum Completed Orders (Optional)',
                  hintText: 'e.g., 5',
                  prefixIcon: Icon(Icons.shopping_bag_outlined),
                  helperText:
                      'Require users to have completed at least this many orders',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    final numValue = int.tryParse(value.trim());
                    if (numValue == null || numValue < 0) {
                      return 'Please enter a valid non-negative number';
                    }
                    if (_firstTimeUserOnly && numValue > 0) {
                      return 'Cannot require orders for first-time users only';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // First-time User Only
              SwitchListTile(
                title: const Text('First-time Users Only'),
                subtitle: const Text(
                  'Only users with 0 completed orders can use this coupon',
                ),
                value: _firstTimeUserOnly,
                onChanged: (value) {
                  setState(() {
                    _firstTimeUserOnly = value;
                    if (value) {
                      _minCompletedOrdersController.clear();
                    }
                  });
                },
                secondary: const Icon(Icons.person_add),
              ),
              const SizedBox(height: 16),
              // Prior Coupon Usage
              DropdownButtonFormField<String>(
                value: _priorCouponUsageType,
                decoration: const InputDecoration(
                  labelText: 'Prior Coupon Usage Check',
                  prefixIcon: Icon(Icons.history),
                  helperText:
                      'Check if user has used coupons before',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'none',
                    child: Text('No Check'),
                  ),
                  DropdownMenuItem(
                    value: 'this_coupon',
                    child: Text('This Specific Coupon'),
                  ),
                  DropdownMenuItem(
                    value: 'any_coupon',
                    child: Text('Any Coupon'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _priorCouponUsageType = value!;
                  });
                },
              ),
              if (_priorCouponUsageType != 'none') ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Usage Required'),
                  subtitle: Text(
                    _priorCouponUsageAllowed
                        ? 'User MUST have used ${_priorCouponUsageType == 'this_coupon' ? 'this coupon' : 'a coupon'} before'
                        : 'User MUST NOT have used ${_priorCouponUsageType == 'this_coupon' ? 'this coupon' : 'a coupon'} before',
                  ),
                  value: _priorCouponUsageAllowed,
                  onChanged: (value) {
                    setState(() {
                      _priorCouponUsageAllowed = value;
                    });
                  },
                  secondary: Icon(
                    _priorCouponUsageAllowed ? Icons.check_circle : Icons.cancel,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // User ID Whitelist
              TextFormField(
                controller: _userIdWhitelistController,
                decoration: const InputDecoration(
                  labelText: 'User ID Whitelist (Optional)',
                  hintText: 'Comma-separated user IDs',
                  prefixIcon: Icon(Icons.people),
                  helperText:
                      'Specific user IDs allowed to use this coupon (comma-separated)',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 24),
              const Divider(thickness: 2),
              const SizedBox(height: 24),
              // Image Upload Section
              const Text(
                'Coupon Image (Optional)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (_existingImageUrl != null && _newImage == null)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: _existingImageUrl!,
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          width: double.infinity,
                          height: 200,
                          color: Colors.grey[300],
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: double.infinity,
                          height: 200,
                          color: Colors.grey[300],
                          child: const Icon(Icons.image_not_supported),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.red,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.close,
                            size: 20,
                            color: Colors.white,
                          ),
                          onPressed: _removeImage,
                        ),
                      ),
                    ),
                  ],
                ),
              if (_newImage != null)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        _newImage!,
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.red,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.close,
                            size: 20,
                            color: Colors.white,
                          ),
                          onPressed: _removeImage,
                        ),
                      ),
                    ),
                  ],
                ),
              if (_existingImageUrl == null && _newImage == null)
                Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.image, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text(
                          'No image selected',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _isUploading ? null : _pickImage,
                icon: const Icon(Icons.add_photo_alternate),
                label: Text(_existingImageUrl != null || _newImage != null
                    ? 'Change Image'
                    : 'Add Image'),
              ),
              const SizedBox(height: 24),
              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveCoupon,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(widget.coupon == null
                          ? 'Create Coupon'
                          : 'Update Coupon'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

