import 'package:flutter/material.dart';
import 'package:foodie_customer/model/AddressModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/pre_validation_service.dart';
import 'package:foodie_customer/widgets/pre_validation/pre_validation_widget.dart';

/// Result when the pre-validation modal is closed.
enum PreValidationModalResult { success, blocked, cancelled }

/// Modal that runs pre-validations and shows PreValidationWidget.
class PreValidationModal {
  /// Shows the pre-validation modal and runs validations.
  /// [onSuccess] is called when user taps Proceed (all validations pass).
  /// Returns the result when modal is closed.
  static Future<PreValidationModalResult> show(
    BuildContext context, {
    required bool isDelivery,
    required String vendorId,
    required double total,
    required String customerId,
    AddressModel? address,
    VendorModel? vendor,
    required VoidCallback onSuccess,
  }) async {
    final result = await showModalBottomSheet<PreValidationModalResult>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PreValidationModalContent(
        isDelivery: isDelivery,
        vendorId: vendorId,
        total: total,
        customerId: customerId,
        address: address,
        vendor: vendor,
        onSuccess: onSuccess,
      ),
    );
    return result ?? PreValidationModalResult.cancelled;
  }
}

class _PreValidationModalContent extends StatefulWidget {
  final bool isDelivery;
  final String vendorId;
  final double total;
  final String customerId;
  final AddressModel? address;
  final VendorModel? vendor;
  final VoidCallback onSuccess;

  const _PreValidationModalContent({
    required this.isDelivery,
    required this.vendorId,
    required this.total,
    required this.customerId,
    this.address,
    this.vendor,
    required this.onSuccess,
  });

  @override
  State<_PreValidationModalContent> createState() =>
      _PreValidationModalContentState();
}

class _PreValidationModalContentState extends State<_PreValidationModalContent> {
  final PreValidationService _service = PreValidationService();
  List<ValidationStepResult> _steps = [];
  bool _canProceed = false;
  bool _hasErrors = false;
  bool _hasWarnings = false;
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    _runValidations();
  }

  Future<void> _runValidations() async {
    if (!mounted) return;

    setState(() {
      _isComplete = false;
      _canProceed = false;
    });

    final input = PreValidationInput(
      isDelivery: widget.isDelivery,
      vendorId: widget.vendorId,
      total: widget.total,
      address: widget.address,
      customerId: widget.customerId,
      vendor: widget.vendor,
    );

    final result = await _service.runValidations(
      input,
      onStepUpdate: (steps) {
        if (mounted) {
          setState(() {
            _steps = steps;
          });
        }
      },
    );

    if (!mounted) return;
    setState(() {
      _steps = result.steps;
      _canProceed = result.canProceed;
      _hasErrors = result.hasErrors;
      _hasWarnings = result.hasWarnings;
      _isComplete = true;
    });
  }

  void _handleProceed() {
    Navigator.of(context).pop(PreValidationModalResult.success);
    widget.onSuccess();
  }

  void _handleCancel() {
    Navigator.of(context).pop(PreValidationModalResult.cancelled);
  }

  @override
  Widget build(BuildContext context) {
    return PreValidationWidget(
      steps: _steps,
      canProceed: _canProceed,
      hasErrors: _hasErrors,
      hasWarnings: _hasWarnings,
      isComplete: _isComplete,
      onRetry: _hasErrors ? _runValidations : null,
      onProceed: _canProceed ? _handleProceed : null,
      onCancel: _handleCancel,
    );
  }
}
