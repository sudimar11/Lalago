import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Page that displays a driver's current location on a map.
class DriverLocationPage extends StatelessWidget {
  final String driverName;
  final double latitude;
  final double longitude;

  const DriverLocationPage({
    super.key,
    required this.driverName,
    required this.latitude,
    required this.longitude,
  });

  @override
  Widget build(BuildContext context) {
    final position = LatLng(latitude, longitude);
    return Scaffold(
      appBar: AppBar(
        title: Text('$driverName - Location'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: position,
          zoom: 16,
        ),
        markers: {
          Marker(
            markerId: const MarkerId('driver'),
            position: position,
            infoWindow: InfoWindow(
              title: driverName.isEmpty ? 'Driver' : driverName,
              snippet: 'Lat: ${latitude.toStringAsFixed(6)}, '
                  'Long: ${longitude.toStringAsFixed(6)}',
            ),
          ),
        },
        myLocationEnabled: false,
        zoomControlsEnabled: true,
      ),
    );
  }
}
