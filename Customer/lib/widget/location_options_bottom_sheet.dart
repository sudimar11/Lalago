import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/AddressModel.dart';
import 'package:foodie_customer/model/User.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/container/ContainerScreen.dart';
import 'package:foodie_customer/ui/deliveryAddressScreen/DeliveryAddressScreen.dart';
import 'package:foodie_customer/ui/location_permission_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_place_picker_mb/google_maps_place_picker.dart';

void showLocationOptionsBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Set your location',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            _OptionTile(
              icon: Icons.my_location,
              title: 'Use current location',
              subtitle: 'Allow location access for accurate results',
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LocationPermissionScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _OptionTile(
              icon: Icons.map_outlined,
              title: 'Set from map',
              subtitle: 'Pick a location on the map',
              onTap: () {
                Navigator.pop(ctx);
                _openPlacePicker(context);
              },
            ),
            const SizedBox(height: 12),
            _OptionTile(
              icon: Icons.edit_location_alt_outlined,
              title: 'Enter address manually',
              subtitle: 'Type your address',
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DeliveryAddressScreen(),
                  ),
                ).then((value) {
                  if (context.mounted && value != null) {
                    MyAppState.selectedPosotion = value as AddressModel;
                    pushAndRemoveUntil(
                      context,
                      ContainerScreen(user: MyAppState.currentUser),
                      false,
                    );
                  }
                });
              },
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _openPlacePicker(BuildContext context) async {
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (ctx) => PlacePicker(
        apiKey: GOOGLE_API_KEY,
        onPlacePicked: (result) {
          MyAppState.selectedPosotion = AddressModel(
            locality: result.formattedAddress,
            location: UserLocation(
              latitude: result.geometry!.location.lat,
              longitude: result.geometry!.location.lng,
            ),
          );
          pushAndRemoveUntil(
            context,
            ContainerScreen(user: MyAppState.currentUser),
            false,
          );
        },
        initialPosition: const LatLng(DEFAULT_LATITUDE, DEFAULT_LONGITUDE),
        useCurrentLocation: false,
        selectInitialPosition: true,
        usePinPointingSearch: true,
        usePlaceDetailSearch: true,
      ),
    ),
  );
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Color(COLOR_PRIMARY)),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}
