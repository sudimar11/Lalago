import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_place_picker_mb/google_maps_place_picker.dart';

extension PlacePickerResultExtension on PickResult {
  /// Returns a cleaned and readable address.
  /// - Uses formattedAddress first
  /// - Removes Plus Codes (e.g. "4HV5+RM7,")
  /// - Falls back to reverse geocoding if needed
  Future<String> getCleanAddress() async {
    String? readableAddress = formattedAddress;

    // If Google gives an empty or weird result, do reverse geocoding
    if (readableAddress == null || readableAddress.isEmpty) {
      final lat = geometry?.location.lat;
      final lng = geometry?.location.lng;
      if (lat != null && lng != null) {
        readableAddress = await LatLng(lat, lng).toReadableAddress();
      }
    }

    // Remove plus code before comma if exists
    if (readableAddress != null && readableAddress.contains(',')) {
      final firstCommaIndex = readableAddress.indexOf(',');
      final firstPart = readableAddress.substring(0, firstCommaIndex);
      if (firstPart.contains('+')) {
        readableAddress = readableAddress.substring(firstCommaIndex + 1).trim();
      }
    }

    return readableAddress?.trim() ?? "Unknown location";
  }
}

extension LatLngReadableAddress on LatLng {
  /// Converts coordinates to a readable address using geocoding
  Future<String> toReadableAddress() async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final parts = [
          place.street,
          place.subLocality,
          place.locality,
          place.administrativeArea,
          place.country,
        ].where((e) => e != null && e.isNotEmpty).toList();
        return parts.join(', ');
      }
      return "Unknown location";
    } catch (e) {
      return "Error getting address";
    }
  }
}
