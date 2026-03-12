import 'dart:async';

import 'package:foodie_customer/model/AddressModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/dispatch_precheck_service.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/restaurant_status_service.dart';
import 'package:foodie_customer/utils/restaurant_eta_delivery_helper.dart';

/// Status for each validation step.
enum ValidationStatus { pending, loading, success, warning, error }

/// Identifier for validation steps.
enum ValidationStepId { restaurant, riderCapacity, address, orderMinimum, eta }

/// Result of a single validation step.
class ValidationStepResult {
  final ValidationStepId id;
  final ValidationStatus status;
  final String label;
  final String? message;
  final String? actionHint;

  const ValidationStepResult({
    required this.id,
    required this.status,
    required this.label,
    this.message,
    this.actionHint,
  });

  ValidationStepResult copyWith({
    ValidationStepId? id,
    ValidationStatus? status,
    String? label,
    String? message,
    String? actionHint,
  }) =>
      ValidationStepResult(
        id: id ?? this.id,
        status: status ?? this.status,
        label: label ?? this.label,
        message: message ?? this.message,
        actionHint: actionHint ?? this.actionHint,
      );
}

/// Result of running all pre-validations.
class PreValidationResult {
  final bool canProceed;
  final List<ValidationStepResult> steps;
  final bool hasErrors;
  final bool hasWarnings;

  const PreValidationResult({
    required this.canProceed,
    required this.steps,
    required this.hasErrors,
    required this.hasWarnings,
  });
}

/// Input data for running pre-validations.
class PreValidationInput {
  final bool isDelivery;
  final String vendorId;
  final double total;
  final AddressModel? address;
  final String customerId;
  final VendorModel? vendor;

  const PreValidationInput({
    required this.isDelivery,
    required this.vendorId,
    required this.total,
    this.address,
    required this.customerId,
    this.vendor,
  });
}

/// Service that orchestrates pre-order validation steps.
class PreValidationService {
  static const Duration _timeout = Duration(seconds: 10);
  final DispatchPrecheckService _dispatchPrecheck = DispatchPrecheckService();

  /// Returns the list of validation steps for the given input.
  List<ValidationStepResult> _initialSteps(PreValidationInput input) {
    final steps = <ValidationStepResult>[];
    steps.add(ValidationStepResult(
      id: ValidationStepId.restaurant,
      status: ValidationStatus.pending,
      label: 'Restaurant availability',
    ));
    if (input.isDelivery) {
      steps.add(ValidationStepResult(
        id: ValidationStepId.riderCapacity,
        status: ValidationStatus.pending,
        label: 'Rider availability',
      ));
      steps.add(ValidationStepResult(
        id: ValidationStepId.address,
        status: ValidationStatus.pending,
        label: 'Delivery address',
      ));
      steps.add(ValidationStepResult(
        id: ValidationStepId.eta,
        status: ValidationStatus.pending,
        label: 'Estimated delivery time',
      ));
    }
    return steps;
  }

  void _updateStep(
    List<ValidationStepResult> steps,
    ValidationStepId id,
    ValidationStatus status, {
    String? message,
    String? actionHint,
  }) {
    final i = steps.indexWhere((s) => s.id == id);
    if (i >= 0) {
      steps[i] = steps[i].copyWith(
        status: status,
        message: message,
        actionHint: actionHint,
      );
    }
  }

  /// Runs all validations and reports progress via [onStepUpdate].
  Future<PreValidationResult> runValidations(
    PreValidationInput input, {
    required void Function(List<ValidationStepResult>) onStepUpdate,
  }) async {
    final steps = _initialSteps(input);
    onStepUpdate(List.from(steps));

    // Step 1: Restaurant status
    _updateStep(steps, ValidationStepId.restaurant, ValidationStatus.loading);
    onStepUpdate(List.from(steps));

    try {
      final status = await RestaurantStatusService
          .checkRestaurantStatusWithClosingSoon(
        input.vendorId,
        closingSoonWithin: const Duration(minutes: 30),
      ).timeout(
        _timeout,
        onTimeout: () => throw TimeoutException('Restaurant check timed out'),
      );

      if (status['exists'] != true) {
        _updateStep(
          steps,
          ValidationStepId.restaurant,
          ValidationStatus.error,
          message: status['error'] as String? ?? 'Restaurant not found',
        );
        onStepUpdate(List.from(steps));
        return PreValidationResult(
          canProceed: false,
          steps: steps,
          hasErrors: true,
          hasWarnings: false,
        );
      }

      final isOpen = status['isOpen'] as bool? ?? false;
      final vendorName =
          (status['vendorName'] ?? 'Restaurant').toString();
      final todayHours =
          (status['todayHours'] ?? 'Closed').toString();

      if (!isOpen) {
        _updateStep(
          steps,
          ValidationStepId.restaurant,
          ValidationStatus.error,
          message: '$vendorName is closed. Open hours: $todayHours',
        );
        onStepUpdate(List.from(steps));
        return PreValidationResult(
          canProceed: false,
          steps: steps,
          hasErrors: true,
          hasWarnings: false,
        );
      }

      final closingSoon = status['closingSoon'] as bool? ?? false;
      final minutesUntilClosing =
          status['minutesUntilClosing'] as int? ?? 0;

      if (closingSoon && minutesUntilClosing > 0) {
        _updateStep(
          steps,
          ValidationStepId.restaurant,
          ValidationStatus.warning,
          message:
              '$vendorName closes in $minutesUntilClosing minutes',
        );
      } else {
        _updateStep(
          steps,
          ValidationStepId.restaurant,
          ValidationStatus.success,
          message: '$vendorName is open',
        );
      }
      onStepUpdate(List.from(steps));

      // Delivery-only steps
      if (input.isDelivery) {
        // Step 2: Rider capacity
        _updateStep(
          steps,
          ValidationStepId.riderCapacity,
          ValidationStatus.loading,
        );
        onStepUpdate(List.from(steps));

        try {
          final precheck = await _dispatchPrecheck.runPrecheck(
            customerId: input.customerId,
            vendorId: input.vendorId,
            deliveryLat: input.address?.location?.latitude,
            deliveryLng: input.address?.location?.longitude,
            deliveryLocality: input.address?.locality,
          ).timeout(
            _timeout,
            onTimeout: () =>
                throw TimeoutException('Rider check timed out'),
          );

          if (!precheck.canCheckout) {
            _updateStep(
              steps,
              ValidationStepId.riderCapacity,
              ValidationStatus.error,
              message: precheck.blockedMessage ??
                  'Our delivery team is at full capacity.',
              actionHint: 'Try again in a few minutes.',
            );
            onStepUpdate(List.from(steps));
            return PreValidationResult(
              canProceed: false,
              steps: steps,
              hasErrors: true,
              hasWarnings: steps
                  .any((s) => s.status == ValidationStatus.warning),
            );
          }

          _updateStep(
            steps,
            ValidationStepId.riderCapacity,
            ValidationStatus.success,
            message:
                '${precheck.activeRiders} rider(s) available in your area',
          );
        } catch (e) {
          _updateStep(
            steps,
            ValidationStepId.riderCapacity,
            ValidationStatus.error,
            message: e is TimeoutException
                ? 'Request timed out. Please retry.'
                : 'Network error. Check connection and retry.',
          );
          onStepUpdate(List.from(steps));
          return PreValidationResult(
            canProceed: false,
            steps: steps,
            hasErrors: true,
            hasWarnings: steps
                .any((s) => s.status == ValidationStatus.warning),
          );
        }
        onStepUpdate(List.from(steps));

        // Step 3: Address validation
        _updateStep(steps, ValidationStepId.address, ValidationStatus.loading);
        onStepUpdate(List.from(steps));

        if (input.address == null) {
          _updateStep(
            steps,
            ValidationStepId.address,
            ValidationStatus.error,
            message: 'Please set a valid delivery address.',
          );
          onStepUpdate(List.from(steps));
          return PreValidationResult(
            canProceed: false,
            steps: steps,
            hasErrors: true,
            hasWarnings: steps
                .any((s) => s.status == ValidationStatus.warning),
          );
        }

        final loc = input.address!.location;
        if (loc == null ||
            (loc.latitude == 0.0 && loc.longitude == 0.0)) {
          _updateStep(
            steps,
            ValidationStepId.address,
            ValidationStatus.error,
            message: 'Please set a valid delivery address with location.',
          );
          onStepUpdate(List.from(steps));
          return PreValidationResult(
            canProceed: false,
            steps: steps,
            hasErrors: true,
            hasWarnings: steps
                .any((s) => s.status == ValidationStatus.warning),
          );
        }

        _updateStep(
          steps,
          ValidationStepId.address,
          ValidationStatus.success,
          message: input.address!.getFullAddress(),
        );
        onStepUpdate(List.from(steps));

        // Step 4: ETA
        _updateStep(steps, ValidationStepId.eta, ValidationStatus.loading);
        onStepUpdate(List.from(steps));

        VendorModel? vendor = input.vendor;
        if (vendor == null) {
          try {
            vendor = await FireStoreUtils()
                .getVendorByVendorID(input.vendorId)
                .timeout(
                  _timeout,
                  onTimeout: () => throw TimeoutException('Vendor fetch timed out'),
                );
          } catch (_) {
            vendor = null;
          }
        }
        if (vendor != null) {
          final distanceKm = RestaurantEtaDeliveryHelper
              .calculateDistanceKm(
            vendor.latitude,
            vendor.longitude,
            loc.latitude,
            loc.longitude,
          );
          final eta =
              RestaurantEtaDeliveryHelper.calculateETA(distanceKm);
          _updateStep(
            steps,
            ValidationStepId.eta,
            ValidationStatus.success,
            message: eta ?? 'Estimated 25-35 min',
          );
        } else {
          _updateStep(
            steps,
            ValidationStepId.eta,
            ValidationStatus.success,
            message: 'Estimated 25-35 min',
          );
        }
        onStepUpdate(List.from(steps));
      }

      final hasErrors =
          steps.any((s) => s.status == ValidationStatus.error);
      final hasWarnings =
          steps.any((s) => s.status == ValidationStatus.warning);

      return PreValidationResult(
        canProceed: !hasErrors,
        steps: steps,
        hasErrors: hasErrors,
        hasWarnings: hasWarnings,
      );
    } catch (e) {
      _updateStep(
        steps,
        ValidationStepId.restaurant,
        ValidationStatus.error,
        message: e is TimeoutException
            ? 'Request timed out. Please retry.'
            : 'Network error. Check connection and retry.',
      );
      onStepUpdate(List.from(steps));
      return PreValidationResult(
        canProceed: false,
        steps: steps,
        hasErrors: true,
        hasWarnings: false,
      );
    }
  }
}
