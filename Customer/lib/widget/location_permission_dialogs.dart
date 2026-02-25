import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/utils/location_error.dart';
import 'package:geolocator/geolocator.dart';

/// Dialog shown when location services are disabled.
/// Settings opens ONLY when user taps "Open Settings".
void showLocationServicesDisabledDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Location Services Disabled'),
      content: const Text(
        'Please enable Location Services in your device settings to use '
        'your current location for nearby restaurants.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
        ElevatedButton(
          onPressed: () async {
            await Geolocator.openLocationSettings();
            if (ctx.mounted) Navigator.pop(ctx);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(COLOR_PRIMARY),
          ),
          child: const Text('Open Settings'),
        ),
      ],
    ),
  );
}

/// Dialog shown when location permission is denied (first denial).
void showLocationPermissionDeniedDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Location Permission'),
      content: const Text(
        'Location permission is required to use your current location for '
        'nearby restaurants and delivery.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Dialog shown when location permission is permanently denied.
/// Settings opens ONLY when user taps "Open Settings".
void showLocationPermanentlyDeniedDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Location Permission'),
      content: const Text(
        'You have previously denied location permission. '
        'Please enable it in app settings to use your current location.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
        ElevatedButton(
          onPressed: () async {
            await Geolocator.openAppSettings();
            if (ctx.mounted) Navigator.pop(ctx);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(COLOR_PRIMARY),
          ),
          child: const Text('Open Settings'),
        ),
      ],
    ),
  );
}

/// Show appropriate dialog based on LocationErrorCode.
void showLocationErrorDialog(BuildContext context, LocationErrorCode code) {
  switch (code) {
    case LocationErrorCode.servicesDisabled:
      showLocationServicesDisabledDialog(context);
      break;
    case LocationErrorCode.permissionDenied:
      showLocationPermissionDeniedDialog(context);
      break;
    case LocationErrorCode.permissionDeniedForever:
      showLocationPermanentlyDeniedDialog(context);
      break;
    case LocationErrorCode.unknown:
      showLocationPermissionDeniedDialog(context);
      break;
  }
}
