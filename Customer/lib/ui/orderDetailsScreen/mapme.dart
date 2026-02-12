import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class OrderMapPage extends StatefulWidget {
  final String orderId;

  const OrderMapPage({Key? key, required this.orderId}) : super(key: key);

  @override
  _OrderMapPageState createState() => _OrderMapPageState();
}

class _OrderMapPageState extends State<OrderMapPage> {
  GoogleMapController? _mapController;
  LatLng? shippingAddressLocation;
  LatLng? driverLocation;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    fetchLocations();
  }

  Future<void> fetchLocations() async {
    try {
      // Fetch the order document
      final orderDoc = await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .get();

      if (orderDoc.exists) {
        final orderData = orderDoc.data() as Map<String, dynamic>;

        // Extract shipping address location from the order
        final shippingLat = orderData['shipping_address']['latitude'];
        final shippingLng = orderData['shipping_address']['longitude'];
        shippingAddressLocation = LatLng(shippingLat, shippingLng);

        // Extract driver location
        final driverLat = orderData['driver_location']['latitude'];
        final driverLng = orderData['driver_location']['longitude'];
        driverLocation = LatLng(driverLat, driverLng);

        // Update the map with markers and polylines
        setState(() {
          _markers = {
            Marker(
              markerId: const MarkerId('shipping_address'),
              position: shippingAddressLocation!,
              infoWindow: const InfoWindow(
                title: 'Shipping Address',
                snippet: 'Delivery Destination',
              ),
            ),
            Marker(
              markerId: const MarkerId('driver'),
              position: driverLocation!,
              infoWindow: const InfoWindow(
                title: 'Driver Location',
                snippet: 'Current Driver Position',
              ),
            ),
          };

          _polylines = {
            Polyline(
              polylineId: const PolylineId('route'),
              points: [driverLocation!, shippingAddressLocation!],
              color: Colors.blue,
              width: 4,
            ),
          };

          // Move camera to fit both markers
          if (_mapController != null) {
            LatLngBounds bounds = LatLngBounds(
              southwest: LatLng(
                (driverLocation!.latitude <= shippingAddressLocation!.latitude)
                    ? driverLocation!.latitude
                    : shippingAddressLocation!.latitude,
                (driverLocation!.longitude <=
                        shippingAddressLocation!.longitude)
                    ? driverLocation!.longitude
                    : shippingAddressLocation!.longitude,
              ),
              northeast: LatLng(
                (driverLocation!.latitude >= shippingAddressLocation!.latitude)
                    ? driverLocation!.latitude
                    : shippingAddressLocation!.latitude,
                (driverLocation!.longitude >=
                        shippingAddressLocation!.longitude)
                    ? driverLocation!.longitude
                    : shippingAddressLocation!.longitude,
              ),
            );
            _mapController!
                .animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
          }
        });
      } else {
        print('Order document does not exist.');
      }
    } catch (e) {
      print('Error fetching locations: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Map'),
      ),
      body: (shippingAddressLocation == null || driverLocation == null)
          ? const Center(child: CircularProgressIndicator())
          : GoogleMap(
              initialCameraPosition: CameraPosition(
                target: shippingAddressLocation!,
                zoom: 14,
              ),
              onMapCreated: (controller) {
                _mapController = controller;
                // Move camera to include both locations
                if (shippingAddressLocation != null && driverLocation != null) {
                  LatLngBounds bounds = LatLngBounds(
                    southwest: LatLng(
                      (driverLocation!.latitude <=
                              shippingAddressLocation!.latitude)
                          ? driverLocation!.latitude
                          : shippingAddressLocation!.latitude,
                      (driverLocation!.longitude <=
                              shippingAddressLocation!.longitude)
                          ? driverLocation!.longitude
                          : shippingAddressLocation!.longitude,
                    ),
                    northeast: LatLng(
                      (driverLocation!.latitude >=
                              shippingAddressLocation!.latitude)
                          ? driverLocation!.latitude
                          : shippingAddressLocation!.latitude,
                      (driverLocation!.longitude >=
                              shippingAddressLocation!.longitude)
                          ? driverLocation!.longitude
                          : shippingAddressLocation!.longitude,
                    ),
                  );
                  _mapController!
                      .animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
                }
              },
              markers: _markers,
              polylines: _polylines,
            ),
    );
  }
}
