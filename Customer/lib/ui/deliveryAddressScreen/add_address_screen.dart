import 'dart:developer';

import 'package:flutter/material.dart';

import 'package:foodie_customer/constants.dart';

import 'package:foodie_customer/main.dart';

import 'package:foodie_customer/model/AddressModel.dart';

import 'package:foodie_customer/model/User.dart';

import 'package:foodie_customer/services/FirebaseHelper.dart';

import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/utils/extensions/latlng_extension.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:google_maps_place_picker_mb/google_maps_place_picker.dart';

import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geocoding/geocoding.dart';

class AddAddressScreen extends StatefulWidget {
  final int? index;

  const AddAddressScreen({super.key, this.index});

  @override
  State<AddAddressScreen> createState() => _AddAddressScreenState();
}

class _AddAddressScreenState extends State<AddAddressScreen> {
  TextEditingController address = TextEditingController();

  TextEditingController landmark = TextEditingController();

  TextEditingController locality = TextEditingController();

  List saveAsList = ['Home', 'Work', 'Hotel', 'other'];

  String selectedSaveAs = "Home";

  UserLocation? userLocation;

  AddressModel addressModel = AddressModel();

  List<AddressModel> shippingAddress = [];

  // Map related variables
  GoogleMapController? _mapController;
  LatLng? _currentLocation;
  Set<Marker> _markers = {};
  bool _isLoadingLocation = false;
  String? _permissionMessage;
  bool _shouldShowSettingsAction = false;

  void _setPermissionMessage(String? message) =>
      setState(() => _permissionMessage = message);

  @override
  void initState() {
    // TODO: implement initState

    getData();
    _getCurrentLocation();

    super.initState();
  }

  getData() {
    if (MyAppState.currentUser != null) {
      if (MyAppState.currentUser!.shippingAddress != null) {
        shippingAddress = MyAppState.currentUser!.shippingAddress!;
      }
    }

    if (widget.index != null) {
      addressModel = shippingAddress[widget.index!];

      address.text = addressModel.address.toString();

      landmark.text = addressModel.landmark.toString();

      locality.text = addressModel.locality.toString();

      selectedSaveAs = addressModel.addressAs.toString();

      userLocation = addressModel.location;
    }

    setState(() {});
  }

  // Request location permission
  Future<PermissionStatus> _requestLocationPermission() async {
    var status = await Permission.location.status;
    if (status.isDenied) {
      status = await Permission.location.request();
    }
    return status;
  }

  // Get current location
  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });
    _setPermissionMessage(null);
    _shouldShowSettingsAction = false;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      final permissionStatus = await _requestLocationPermission();
      if (!permissionStatus.isGranted) {
        final isPermanentlyDenied = permissionStatus.isPermanentlyDenied;
        _setPermissionMessage(
          isPermanentlyDenied
              ? 'Location permission is permanently denied. '
                  'Please enable it in Settings.'
              : 'Location permission is required to show your current '
                  'location.',
        );
        _shouldShowSettingsAction = isPermanentlyDenied;
        setState(() {
          _isLoadingLocation = false;
          _currentLocation ??= userLocation != null
              ? LatLng(
                  userLocation!.latitude,
                  userLocation!.longitude,
                )
              : const LatLng(-33.8567844, 151.213108);
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _isLoadingLocation = false;
      });

      // Add marker for current location
      _addMarker(_currentLocation!, "Current Location");

      // Update userLocation if not already set
      if (userLocation == null) {
        userLocation = UserLocation(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      }

      // Get address for current location
      _getAddressFromCoordinates(_currentLocation!);

      // Animate camera to current location
      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(_currentLocation!),
        );
      }
    } catch (e) {
      log("Error getting current location: $e");
      _setPermissionMessage(
        'Unable to get current location. Please try again.',
      );
      setState(() {
        _isLoadingLocation = false;
      });

    }
  }

  // Add marker to map
  void _addMarker(LatLng position, String title) {
    setState(() {
      _markers.clear();
      _markers.add(
        Marker(
          markerId: MarkerId('selected_location'),
          position: position,
          infoWindow: InfoWindow(title: title),
        ),
      );
    });
  }

  // Handle map tap to select location
  void _onMapTap(LatLng position) {
    _addMarker(position, "Selected Location");
    userLocation = UserLocation(
      latitude: position.latitude,
      longitude: position.longitude,
    );
    _getAddressFromCoordinates(position);
  }

  // Get address from coordinates
  Future<void> _getAddressFromCoordinates(LatLng position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        String address = [
          place.street,
          place.locality,
          place.administrativeArea,
          place.country,
        ].where((element) => element != null && element.isNotEmpty).join(", ");

        setState(() {
          locality.text = address;
        });
      }
    } catch (e) {
      log("Error getting address from coordinates: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Text(
          'Add Address',
          style: TextStyle(
              fontFamily: "Poppinsm",
              color: isDarkMode(context) ? Colors.white : Colors.black),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              // Map Section
              Card(
                elevation: 0.5,
                color: isDarkMode(context)
                    ? Color(DARK_BG_COLOR)
                    : Color(0XFFFFFFFF),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: Container(
                  height: 250,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      children: [
                        _currentLocation == null
                            ? Center(
                                child: _isLoadingLocation
                                    ? Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          CircularProgressIndicator(
                                            color: Color(COLOR_PRIMARY),
                                          ),
                                          SizedBox(height: 10),
                                          Text(
                                            "Getting your location...",
                                            style: TextStyle(
                                              fontFamily: "Poppinsm",
                                              color: isDarkMode(context)
                                                  ? Colors.white
                                                  : Colors.black,
                                            ),
                                          ),
                                        ],
                                      )
                                    : Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.location_off,
                                            size: 50,
                                            color: Colors.grey,
                                          ),
                                          SizedBox(height: 10),
                                          Text(
                                            "Location not available",
                                            style: TextStyle(
                                              fontFamily: "Poppinsm",
                                              color: Colors.grey,
                                            ),
                                          ),
                                          SizedBox(height: 10),
                                          ElevatedButton.icon(
                                            onPressed: _getCurrentLocation,
                                            icon: Icon(Icons.refresh),
                                            label: Text("Retry"),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Color(COLOR_PRIMARY),
                                              foregroundColor: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                              )
                            : GoogleMap(
                                onMapCreated: (GoogleMapController controller) {
                                  _mapController = controller;
                                },
                                initialCameraPosition: CameraPosition(
                                  target: _currentLocation!,
                                  zoom: 15.0,
                                ),
                                markers: _markers,
                                onTap: _onMapTap,
                                myLocationEnabled: true,
                                myLocationButtonEnabled: false,
                                zoomControlsEnabled: false,
                                mapType: MapType.normal,
                              ),
                        // Floating action button for current location
                        if (_currentLocation != null)
                          Positioned(
                            top: 10,
                            right: 10,
                            child: FloatingActionButton(
                              mini: true,
                              backgroundColor: Color(COLOR_PRIMARY),
                              onPressed: _getCurrentLocation,
                              child: Icon(
                                Icons.my_location,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: 16),
              if (_permissionMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: SelectableText.rich(
                    TextSpan(
                      text: _permissionMessage,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                      ),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (_shouldShowSettingsAction)
                TextButton(
                  onPressed: () {
                    openAppSettings();
                  },
                  child: const Text('Open Settings'),
                ),
              Card(
                elevation: 0.5,
                color: isDarkMode(context)
                    ? Color(DARK_BG_COLOR)
                    : Color(0XFFFFFFFF),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: () {
                          log("sadhadhashdasdas");
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PlacePicker(
                                apiKey: GOOGLE_API_KEY,

                                onPlacePicked: (result) async {
                                  final readableAddress =
                                      await result.getCleanAddress();

                                  locality.text = readableAddress;

                                  userLocation = UserLocation(
                                    latitude: result.geometry!.location.lat,
                                    longitude: result.geometry!.location.lng,
                                  );

                                  log('Readable Address: $readableAddress');

                                  Navigator.of(context).pop();
                                },

                                initialPosition:
                                    LatLng(-33.8567844, 151.213108),

                                useCurrentLocation: true,

                                selectInitialPosition: true,

                                usePinPointingSearch: true,

                                usePlaceDetailSearch: true,

                                zoomGesturesEnabled: true,

                                zoomControlsEnabled: true,

                                resizeToAvoidBottomInset:
                                    false, // only works in page mode, less flickery, remove if wrong offsets
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Icon(Icons.location_searching_sharp,
                                  color: Color(COLOR_PRIMARY)),
                              SizedBox(
                                width: 10,
                              ),
                              Text(
                                "Choose location *",
                                style: TextStyle(
                                    color: Color(COLOR_PRIMARY),
                                    fontFamily: "Poppinsm",
                                    fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Card(
                elevation: 0.5,
                color: isDarkMode(context)
                    ? Color(DARK_BG_COLOR)
                    : Color(0XFFFFFFFF),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          "Save address as *",
                          style:
                              TextStyle(fontFamily: "Poppinsm", fontSize: 14),
                        ),
                      ),
                      SizedBox(
                        height: 10,
                      ),
                      SizedBox(
                        height: 34,
                        child: ListView.builder(
                          itemCount: saveAsList.length,
                          shrinkWrap: true,
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          scrollDirection: Axis.horizontal,
                          itemBuilder: (context, index) {
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  selectedSaveAs = saveAsList[index].toString();
                                });
                              },
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 5),
                                child: Container(
                                  decoration: BoxDecoration(
                                      color: selectedSaveAs ==
                                              saveAsList[index].toString()
                                          ? Color(COLOR_PRIMARY)
                                          : isDarkMode(context)
                                              ? Colors.black
                                              : Colors.grey
                                                  .withValues(alpha: 0.20),
                                      borderRadius: const BorderRadius.all(
                                          Radius.circular(20))),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 30),
                                    child: Center(
                                      child: Text(
                                        saveAsList[index].toString(),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: selectedSaveAs ==
                                                  saveAsList[index].toString()
                                              ? Colors.white
                                              : Colors.black,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        height: 30,
                      ),
                      Container(
                        padding: const EdgeInsetsDirectional.only(
                            start: 20, end: 20, bottom: 10, top: 5),
                        child: TextFormField(
                            controller: address,
                            textAlignVertical: TextAlignVertical.center,
                            textInputAction: TextInputAction.next,
                            validator: validateEmptyField,

                            // onSaved: (text) => line1 = text,

                            keyboardType: TextInputType.streetAddress,
                            cursorColor: Color(COLOR_PRIMARY),
                            decoration: InputDecoration(
                              contentPadding: EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 10),
                              labelText:
                                  'Flat / House / Flore / Building *',
                              labelStyle: TextStyle(
                                  color: Color(0Xff696A75), fontSize: 17),
                              hintStyle: TextStyle(color: Colors.grey.shade400),
                              focusedBorder: OutlineInputBorder(
                                borderSide:
                                    BorderSide(color: Color(COLOR_PRIMARY)),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.error),
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              focusedErrorBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.error),
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide:
                                    BorderSide(color: Color(0XFFB1BCCA)),
                              ),
                            )),
                      ),
                      Container(
                        padding: const EdgeInsetsDirectional.only(
                            start: 20, end: 20, bottom: 10, top: 5),
                        child: TextFormField(
                          controller: locality,
                          textAlignVertical: TextAlignVertical.center,
                          textInputAction: TextInputAction.next,
                          validator: validateEmptyField,
                          keyboardType: TextInputType.multiline,
                          maxLines: null,
                          cursorColor: Color(COLOR_PRIMARY),
                          readOnly: locality.text
                              .isNotEmpty, // Make it non-editable if it has a value
                          decoration: InputDecoration(
                            contentPadding: EdgeInsets.symmetric(
                                vertical: 14, horizontal: 10),
                            labelText: 'Area / Sector / Locality *',
                            labelStyle: TextStyle(
                                color: Color(0Xff696A75), fontSize: 17),
                            hintStyle: TextStyle(color: Colors.grey.shade400),
                            focusedBorder: OutlineInputBorder(
                              borderSide:
                                  BorderSide(color: Color(COLOR_PRIMARY)),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.error),
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.error),
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Color(0XFFB1BCCA)),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsetsDirectional.only(
                            start: 20, end: 20, bottom: 10, top: 5),
                        child: TextFormField(
                            controller: landmark,
                            textAlignVertical: TextAlignVertical.center,
                            textInputAction: TextInputAction.next,
                            validator: validateEmptyField,

                            // onSaved: (text) => line1 = text,

                            keyboardType: TextInputType.streetAddress,
                            cursorColor: Color(COLOR_PRIMARY),
                            decoration: InputDecoration(
                              contentPadding: EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 10),
                              labelText: 'Nearby Landmark (Optional)',
                              labelStyle: TextStyle(
                                  color: Color(0Xff696A75), fontSize: 17),
                              hintStyle: TextStyle(color: Colors.grey.shade400),
                              focusedBorder: OutlineInputBorder(
                                borderSide:
                                    BorderSide(color: Color(COLOR_PRIMARY)),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.error),
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              focusedErrorBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.error),
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide:
                                    BorderSide(color: Color(0XFFB1BCCA)),
                              ),
                            )),
                      ),
                      SizedBox(
                        height: 20,
                      ),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10.0, horizontal: 10),
                          child: SizedBox(
                            width: 160,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.all(10),
                                backgroundColor: Color(COLOR_PRIMARY),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () async {
                                if (userLocation == null) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(
                                    content: Text("Please select Location"),
                                    backgroundColor: Colors.red.shade400,
                                    duration: Duration(seconds: 1),
                                  ));

                                  log("Save button pressed: No location selected.");
                                } else if (address.text.isEmpty) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(
                                    content:
                                        Text("Please Enter House / Building"),
                                    backgroundColor: Colors.red.shade400,
                                    duration: Duration(seconds: 1),
                                  ));

                                  log("Save button pressed: Address field is empty.");
                                } else if (locality.text.isEmpty) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(
                                    content: Text(
                                        "Please Enter Area / Sector / locality"),
                                    backgroundColor: Colors.red.shade400,
                                    duration: Duration(seconds: 1),
                                  ));

                                  log("Save button pressed: Locality field is empty.");
                                } else {
                                  log("Save button pressed: All validations passed.");

                                  if (widget.index != null) {
                                    addressModel.location = userLocation;

                                    addressModel.addressAs = selectedSaveAs;

                                    addressModel.locality = locality.text;

                                    addressModel.address = address.text;

                                    addressModel.landmark = landmark.text;

                                    shippingAddress.removeAt(widget.index!);

                                    shippingAddress.insert(
                                        widget.index!, addressModel);

                                    log("Updated address at index ${widget.index}: ${addressModel.toJson()}");
                                  } else {
                                    addressModel.id = Uuid().v4();

                                    addressModel.location = userLocation;

                                    addressModel.addressAs = selectedSaveAs;

                                    addressModel.locality = locality.text;

                                    addressModel.address = address.text;

                                    addressModel.landmark = landmark.text;

                                    addressModel.isDefault =
                                        shippingAddress.isEmpty ? true : false;

                                    bool alreadyExists = shippingAddress.any(
                                        (a) =>
                                            a.address == addressModel.address &&
                                            a.locality ==
                                                addressModel.locality &&
                                            a.location?.latitude ==
                                                addressModel
                                                    .location!.latitude &&
                                            a.location?.longitude ==
                                                addressModel
                                                    .location!.longitude);

                                    if (!alreadyExists) {
                                      addressModel.id = Uuid().v4();
                                      addressModel.isDefault =
                                          shippingAddress.isEmpty
                                              ? true
                                              : false;
                                      shippingAddress.add(addressModel);
                                      log("Added new address: ${addressModel.toJson()}");
                                    } else {
                                      log("Duplicate address detected. Not adding again.");
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              "This address already exists."),
                                          backgroundColor: Colors.orange,
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                      return;
                                    }

                                    log("Added new address: ${addressModel.toJson()}");
                                  }

                                  setState(() {});

                                  log("User ID: ${MyAppState.currentUser!.userID}");

                                  MyAppState.currentUser!.shippingAddress =
                                      shippingAddress;

                                  // Update the current location field along with the shippingAddress

                                  try {
                                    MyAppState.currentUser!.location =
                                        UserLocation(
                                      latitude: userLocation!.latitude,
                                      longitude: userLocation!.longitude,
                                    );

                                    await FireStoreUtils.updateCurrentUser(
                                        MyAppState.currentUser!);

                                    log("User data successfully updated in Firestore.");

                                    log("Updated location: ${MyAppState.currentUser!.location.toJson()}");
                                    
                                    // Re-determine the default address from the updated list
                                    final resolvedDefaultAddress = MyAppState.resolveDefaultAddress(
                                        MyAppState.currentUser!.shippingAddress);
                                    if (resolvedDefaultAddress != null) {
                                      MyAppState.selectedPosotion = resolvedDefaultAddress;
                                    }
                                  } catch (e) {
                                    log("Error updating user data in Firestore: $e");
                                  }

                                  Navigator.pop(context, true);
                                }
                              },
                              child: Text(
                                'Save',
                                style: TextStyle(
                                    color: isDarkMode(context)
                                        ? Colors.black
                                        : Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18),
                              ),
                            ),
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
