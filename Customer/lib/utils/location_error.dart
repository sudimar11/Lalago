/// Error codes returned by getCurrentLocation when location cannot be obtained.
/// Use these to show the appropriate user-facing dialog with optional
/// "Open Settings" button.
enum LocationErrorCode {
  servicesDisabled,
  permissionDenied,
  permissionDeniedForever,
  unknown,
}

/// Parses error from getCurrentLocation Future.error result.
LocationErrorCode parseLocationError(Object error) {
  if (error is LocationErrorCode) return error;
  if (error is String) {
    switch (error) {
      case 'Location permissions are denied':
        return LocationErrorCode.permissionDenied;
      default:
        return LocationErrorCode.unknown;
    }
  }
  return LocationErrorCode.unknown;
}
