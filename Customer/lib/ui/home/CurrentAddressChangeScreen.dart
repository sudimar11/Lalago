import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/AddressModel.dart';
import 'package:foodie_customer/model/User.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_place_picker_mb/google_maps_place_picker.dart';

class CurrentAddressChangeScreen extends StatefulWidget {
  const CurrentAddressChangeScreen({
    Key? key,
  }) : super(key: key);

  @override
  _CurrentAddressChangeScreenState createState() =>
      _CurrentAddressChangeScreenState();
}

class _CurrentAddressChangeScreenState
    extends State<CurrentAddressChangeScreen> {
  final kInitialPosition = LatLng(-33.8567844, 151.213108);
  final _formKey = GlobalKey<FormState>();

  // String? line1, line2, zipCode, city;
  String? country;
  var street = TextEditingController();
  var street1 = TextEditingController();
  var landmark = TextEditingController();
  var landmark1 = TextEditingController();
  var zipcode = TextEditingController();
  var zipcode1 = TextEditingController();
  var city = TextEditingController();
  var city1 = TextEditingController();
  var cutries = TextEditingController();
  var cutries1 = TextEditingController();
  var lat;
  var long;

  AutovalidateMode _autoValidateMode = AutovalidateMode.disabled;

  @override
  void dispose() {
    street.dispose();
    landmark.dispose();
    city.dispose();
    // cutries.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MyAppState.currentUser != null) {
      // if(MyAppState.currentUser!.shippingAddress.country != ''){
      //   country = MyAppState.currentUser!.shippingAddress.country;
      // }
      // street.text = MyAppState.currentUser!.shippingAddress.line1;
      // landmark.text = MyAppState.currentUser!.shippingAddress.line2;
      // city.text = MyAppState.currentUser!.shippingAddress.city;
      // zipcode.text = MyAppState.currentUser!.shippingAddress.postalCode;
      // cutries.text = MyAppState.currentUser!.shippingAddress.country;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Change Address',
          style: TextStyle(
              color: isDarkMode(context) ? Colors.white : Colors.black),
        ),
      ),
      body: Container(
          color: isDarkMode(context) ? null : Color(0XFFF1F4F7),
          child: Form(
              key: _formKey,
              autovalidateMode: _autoValidateMode,
              child: SingleChildScrollView(
                  child: Column(children: [
                SizedBox(
                  height: 40,
                ),
                Card(
                  elevation: 0.5,
                  color: isDarkMode(context)
                      ? Color(DARK_BG_COLOR)
                      : Color(0XFFFFFFFF),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  margin: EdgeInsets.only(left: 20, right: 20),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsetsDirectional.only(
                            start: 20, end: 20, bottom: 10),
                        child: TextFormField(
                            // controller: street,
                            controller: street1.text.isEmpty ? street : street1,
                            textAlignVertical: TextAlignVertical.center,
                            textInputAction: TextInputAction.next,
                            validator: validateEmptyField,
                            // onSaved: (text) => line1 = text,
                            onSaved: (text) => street.text = text!,
                            style: TextStyle(fontSize: 18.0),
                            keyboardType: TextInputType.streetAddress,
                            cursorColor: Color(COLOR_PRIMARY),
                            // initialValue:
                            //     MyAppState.currentUser!.shippingAddress.line1,
                            decoration: InputDecoration(
                              // contentPadding: EdgeInsets.symmetric(horizontal: 24),
                              labelText: 'Street 1',
                              labelStyle: TextStyle(
                                  color: Color(0Xff696A75), fontSize: 17),
                              hintStyle: TextStyle(color: Colors.grey.shade400),
                              focusedBorder: UnderlineInputBorder(
                                borderSide:
                                    BorderSide(color: Color(COLOR_PRIMARY)),
                              ),
                              errorBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.error),
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              focusedErrorBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.error),
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              enabledBorder: UnderlineInputBorder(
                                borderSide:
                                    BorderSide(color: Color(0XFFB1BCCA)),
                                // borderRadius: BorderRadius.circular(8.0),
                              ),
                            )),
                      ),
                      // ListTile(
                      //   contentPadding:
                      //       const EdgeInsetsDirectional.only(start: 40, end: 30, top: 24),
                      //   leading: Container(
                      //     // width: 0,
                      //     child: Text(
                      //       'Street 2',
                      //       style: TextStyle(fontSize: 16),
                      //     ),
                      //   ),
                      // ),
                      Container(
                        padding: const EdgeInsetsDirectional.only(
                            start: 20, end: 20, bottom: 10),
                        child: TextFormField(
                          // controller: _controller,
                          controller:
                              landmark1.text.isEmpty ? landmark : landmark1,
                          textAlignVertical: TextAlignVertical.center,
                          textInputAction: TextInputAction.next,
                          validator: validateEmptyField,
                          onSaved: (text) => landmark.text = text!,
                          style: TextStyle(fontSize: 18.0),
                          keyboardType: TextInputType.streetAddress,
                          cursorColor: Color(COLOR_PRIMARY),
                          // initialValue:
                          //     MyAppState.currentUser!.shippingAddress.line2,
                          decoration: InputDecoration(
                            // contentPadding: EdgeInsets.symmetric(horizontal: 24),
                            labelText: 'Landmark',
                            labelStyle: TextStyle(
                                color: Color(0Xff696A75), fontSize: 17),
                            hintStyle: TextStyle(color: Colors.grey.shade400),
                            focusedBorder: UnderlineInputBorder(
                              borderSide:
                                  BorderSide(color: Color(COLOR_PRIMARY)),
                            ),
                            errorBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.error),
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            focusedErrorBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.error),
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Color(0XFFB1BCCA)),
                              // borderRadius: BorderRadius.circular(8.0),
                            ),
                          ),
                        ),
                      ),
                      // ListTile(
                      //   contentPadding:
                      //       const EdgeInsetsDirectional.only(start: 40, end: 30, top: 24),
                      //   leading: Container(
                      //     // width: 0,
                      //     child: Text(
                      //       'Zip Code',
                      //       style: TextStyle(fontSize: 16),
                      //     ),
                      //   ),
                      // ),
                      Container(
                        padding: const EdgeInsetsDirectional.only(
                            start: 20, end: 20, bottom: 10),
                        child: TextFormField(
                          controller:
                              zipcode1.text.isEmpty ? zipcode : zipcode1,
                          textAlignVertical: TextAlignVertical.center,
                          textInputAction: TextInputAction.next,
                          validator: validateEmptyField,
                          onSaved: (text) => zipcode.text = text!,
                          style: TextStyle(fontSize: 18.0),
                          keyboardType: TextInputType.phone,
                          cursorColor: Color(COLOR_PRIMARY),
                          // initialValue: MyAppState
                          //     .currentUser!.shippingAddress.postalCode,
                          decoration: InputDecoration(
                            // contentPadding: EdgeInsets.symmetric(horizontal: 24),
                            labelText: 'Zip Code',
                            labelStyle: TextStyle(
                                color: Color(0Xff696A75), fontSize: 17),
                            hintStyle: TextStyle(color: Colors.grey.shade400),
                            focusedBorder: UnderlineInputBorder(
                              borderSide:
                                  BorderSide(color: Color(COLOR_PRIMARY)),
                            ),
                            errorBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.error),
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            focusedErrorBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.error),
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Color(0XFFB1BCCA)),
                              // borderRadius: BorderRadius.circular(8.0),
                            ),
                          ),
                        ),
                      ),
                      // ListTile(
                      //   contentPadding:
                      //       const EdgeInsetsDirectional.only(start: 40, end: 30, top: 24),
                      //   leading: Container(
                      //     // width: 0,
                      //     child: Text(
                      //       'City',
                      //       style: TextStyle(fontSize: 16),
                      //     ),
                      //   ),
                      // ),
                      Container(
                          padding: const EdgeInsetsDirectional.only(
                              start: 20, end: 20, bottom: 10),
                          child: TextFormField(
                            controller: city1.text.isEmpty ? city : city1,
                            textAlignVertical: TextAlignVertical.center,
                            textInputAction: TextInputAction.next,
                            validator: validateEmptyField,
                            onSaved: (text) => city.text = text!,
                            style: TextStyle(fontSize: 18.0),
                            keyboardType: TextInputType.streetAddress,
                            cursorColor: Color(COLOR_PRIMARY),
                            // initialValue:
                            //     MyAppState.currentUser!.shippingAddress.city,
                            decoration: InputDecoration(
                              // contentPadding: EdgeInsets.symmetric(horizontal: 24),
                              labelText: 'City',
                              labelStyle: TextStyle(
                                  color: Color(0Xff696A75), fontSize: 17),
                              hintStyle: TextStyle(color: Colors.grey.shade400),
                              focusedBorder: UnderlineInputBorder(
                                borderSide:
                                    BorderSide(color: Color(COLOR_PRIMARY)),
                              ),
                              errorBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.error),
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              focusedErrorBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.error),
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              enabledBorder: UnderlineInputBorder(
                                borderSide:
                                    BorderSide(color: Color(0XFFB1BCCA)),
                                // borderRadius: BorderRadius.circular(8.0),
                              ),
                            ),
                          )),

                      Container(
                          padding: const EdgeInsetsDirectional.only(
                              start: 20, end: 20, bottom: 10),
                          child: TextFormField(
                            controller:
                                cutries1.text.isEmpty ? cutries : cutries1,
                            textAlignVertical: TextAlignVertical.center,
                            textInputAction: TextInputAction.next,
                            validator: validateEmptyField,
                            onSaved: (text) => cutries.text = text!,
                            style: TextStyle(fontSize: 18.0),
                            keyboardType: TextInputType.streetAddress,
                            cursorColor: Color(COLOR_PRIMARY),
                            // initialValue:
                            //     MyAppState.currentUser!.shippingAddress.city,
                            decoration: InputDecoration(
                              // contentPadding: EdgeInsets.symmetric(horizontal: 24),
                              labelText: 'Country',
                              labelStyle: TextStyle(
                                  color: Color(0Xff696A75), fontSize: 17),
                              hintStyle: TextStyle(color: Colors.grey.shade400),
                              focusedBorder: UnderlineInputBorder(
                                borderSide:
                                    BorderSide(color: Color(COLOR_PRIMARY)),
                              ),
                              errorBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.error),
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              focusedErrorBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.error),
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              enabledBorder: UnderlineInputBorder(
                                borderSide:
                                    BorderSide(color: Color(0XFFB1BCCA)),
                                // borderRadius: BorderRadius.circular(8.0),
                              ),
                            ),
                          )),
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Card(
                            child: ListTile(
                                leading: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // ImageIcon(
                                    //   AssetImage('assets/images/current_location1.png'),
                                    //   size: 23,
                                    //   color: Color(COLOR_PRIMARY),
                                    // ),
                                    Icon(
                                      Icons.location_searching_rounded,
                                      color: Color(COLOR_PRIMARY),
                                    ),
                                  ],
                                ),
                                title: Text(
                                  "Current Location",
                                  style: TextStyle(color: Color(COLOR_PRIMARY)),
                                ),
                                subtitle: Text(
                                  "Using GPS",
                                  style: TextStyle(color: Color(COLOR_PRIMARY)),
                                ),
                                onTap: () async {
                                  List<Placemark> placemarks =
                                      await placemarkFromCoordinates(
                                    kInitialPosition.latitude,
                                    kInitialPosition.longitude,
                                  );

                                  Placemark place = placemarks.first;
                                  street1.text = place.street ?? '';
                                  landmark1.text = place.subLocality ?? '';
                                  city1.text = place.locality ?? '';
                                  cutries1.text = place.country ?? '';
                                  zipcode1.text = place.postalCode ?? '';
                                  lat = kInitialPosition.latitude;
                                  long = kInitialPosition.longitude;

                                  setState(() {});
                                })),
                      ),
                      SizedBox(
                        height: 40,
                      )
                    ],
                  ),
                ),
                SizedBox()
              ])))),
      bottomNavigationBar: Container(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 25),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(15),
              backgroundColor: Color(COLOR_PRIMARY),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => validateForm(),
            child: Text(
              'DONE',
              style: TextStyle(
                  color: isDarkMode(context) ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18),
            ),
          ),
        ),
      ),
    );
  }

  validateForm() async {
    if (_formKey.currentState?.validate() ?? false) {
      _formKey.currentState!.save();

      if (MyAppState.currentUser != null &&
          MyAppState.currentUser!.shippingAddress != null &&
          MyAppState.currentUser!.shippingAddress!.isNotEmpty) {
        // Access the first location from the shippingAddress list
        var userLocation = MyAppState.currentUser!.shippingAddress![0].location;

        // Check if the user's current location is not set (both lat and long are 0)
        if ((userLocation?.latitude ?? 0) == 0 &&
            (userLocation?.longitude ?? 0) == 0) {
          if (lat == 0 && long == 0) {
            await showDialog(
              barrierDismissible: false,
              context: context,
              builder: (_) {
                return AlertDialog(
                  content: Text(
                    "Please select current address using GPS location. Move pin to exact location",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        hideProgress();
                        Navigator.pop(context, true);
                      },
                      child: Text('OK'),
                    ),
                  ],
                );
              },
            );
            return; // Exit if user hasn't set the GPS location
          }
        } else {
          // Use the existing location if lat/long are not set
          if ((lat == null || long == null) || (lat == 0 && long == 0)) {
            lat = userLocation?.latitude ?? 0.0;
            long = userLocation?.longitude ?? 0.0;
          }
        }

        // Show progress while saving
        showProgress(context, 'Saving Address...', true);

        try {
          // Set the user's location
          MyAppState.currentUser!.location = UserLocation(
            latitude: lat!,
            longitude: long!,
          );

          // Preserve the existing address ID if updating
          String? existingId = MyAppState.currentUser!.shippingAddress![0].id;

          // Update the user's address model with the correct fields
          AddressModel userAddress = AddressModel(
            id: existingId, // Preserve the ID
            address: street.text,
            landmark: landmark.text,
            locality: city.text,
            location: MyAppState.currentUser!.location,
            isDefault: true, // Keep as default
          );

          // Save the new address model to shippingAddress and update Firestore
          MyAppState.currentUser!.shippingAddress![0] = userAddress;
          await FireStoreUtils.updateCurrentUserAddress(userAddress);

          // Re-determine the default address from the updated list
          final resolvedDefaultAddress = MyAppState.resolveDefaultAddress(
              MyAppState.currentUser!.shippingAddress);
          if (resolvedDefaultAddress != null) {
            MyAppState.selectedPosition = resolvedDefaultAddress;
          } else {
            // Fallback: Update selectedPosition with the new address model
            MyAppState.selectedPosition = userAddress;
          }

          hideProgress();
        } catch (e) {
          hideProgress();
          print('❌ Error saving address: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to save address. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      } else {
        // If shippingAddress is empty or null, initialize it with a new address
        showProgress(context, 'Saving Address...', true);

        try {
          // Initialize shippingAddress list if null
          if (MyAppState.currentUser!.shippingAddress == null) {
            MyAppState.currentUser!.shippingAddress = [];
          }

          // Create a new address
          AddressModel newAddress = AddressModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            address: street.text,
            landmark: landmark.text,
            locality: city.text,
            location: UserLocation(latitude: lat!, longitude: long!),
            isDefault: true,
          );

          // Add to shipping address list
          MyAppState.currentUser!.shippingAddress!.add(newAddress);

          // Update user location
          MyAppState.currentUser!.location = UserLocation(
            latitude: lat!,
            longitude: long!,
          );

          // Save to Firestore
          await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!);

          // Update selected position
          MyAppState.selectedPosition = newAddress;

          hideProgress();
        } catch (e) {
          hideProgress();
          print('❌ Error creating address: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to create address. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      // Construct the address as a single string
      String passAddress =
          '${street.text}, ${landmark.text}, ${city.text}, ${zipcode.text}, ${cutries.text}';
      Navigator.pop(context, passAddress);
    } else {
      // Set form to auto-validate if validation fails
      setState(() {
        _autoValidateMode = AutovalidateMode.onUserInteraction;
      });
    }
  }
}
