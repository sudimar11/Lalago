import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:foodie_customer/constants.dart';

import 'package:foodie_customer/main.dart';

import 'package:foodie_customer/model/AddressModel.dart';

import 'package:foodie_customer/model/User.dart';

import 'package:foodie_customer/services/helper.dart';

import 'package:foodie_customer/ui/container/ContainerScreen.dart';

import 'package:foodie_customer/widget/permission_dialog.dart';

import 'package:geocoding/geocoding.dart';

import 'package:geolocator/geolocator.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:google_maps_place_picker_mb/google_maps_place_picker.dart';

import 'deliveryAddressScreen/DeliveryAddressScreen.dart';

class LocationPermissionScreen extends StatefulWidget {
  const LocationPermissionScreen({Key? key}) : super(key: key);

  @override
  _LocationPermissionScreenState createState() =>
      _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen> {
  String? _permissionMessage;
  static const _debugLogPath =
      '/Users/sudimard/Desktop/customer/.cursor/debug.log';
  static const _debugChannel = MethodChannel('cursor.debug/keychain');

  void _appendRuntimeDebugLog({
    required String hypothesisId,
    required String location,
    required String message,
    required Map<String, dynamic> data,
  }) {
    final payload = <String, dynamic>{
      'sessionId': 'debug-session',
      'runId': 'pre-fix',
      'hypothesisId': hypothesisId,
      'location': location,
      'message': message,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    try {
      File(_debugLogPath).writeAsStringSync(
        '${jsonEncode(payload)}\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  void _setPermissionMessage(String? message) {
    setState(() {
      _permissionMessage = message;
    });
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return PermissionDialog();
      },
    );
  }

  Future<void> _handleUseCurrentLocation() async {
    _setPermissionMessage(null);
    log('[IOS_LOC] Use current location tapped');

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    log('[IOS_LOC] serviceEnabled=$serviceEnabled');
    if (!serviceEnabled) {
      _setPermissionMessage(
        'Location services are disabled. '
        'Please enable Location Services in Settings.',
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    log('[IOS_LOC] checkPermission=$permission');

    if (permission == LocationPermission.denied) {
      try {
        permission = await Geolocator.requestPermission();
        log('[IOS_LOC] requestPermission=$permission');
      } catch (e) {
        _setPermissionMessage(
          'Failed to request location permission. Please try again.',
        );
        log('[IOS_LOC] requestPermission failed: $e');
        return;
      }
    }

    if (permission == LocationPermission.denied) {
      _setPermissionMessage(
        'Location permission is required to use your current location.',
      );
      return;
    }

    if (permission == LocationPermission.deniedForever) {
      _setPermissionMessage(
        'Location permission is permanently denied. '
        'Please enable it in Settings.',
      );
      _showPermissionDialog();
      return;
    }

    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      _setPermissionMessage(
        'Location permission is not granted. Please try again.',
      );
      return;
    }

    await showProgress(context, "Please wait...", false);

    AddressModel addressModel = AddressModel();

    try {
      final Position newLocalData = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      await placemarkFromCoordinates(
        newLocalData.latitude,
        newLocalData.longitude,
      ).then((valuePlaceMaker) {
        final Placemark placeMark = valuePlaceMaker[0];

        setState(() {
          addressModel.location = UserLocation(
            latitude: newLocalData.latitude,
            longitude: newLocalData.longitude,
          );

          final currentLocation =
              "${placeMark.name}, ${placeMark.subLocality}, "
              "${placeMark.locality}, ${placeMark.administrativeArea}, "
              "${placeMark.postalCode}, ${placeMark.country}";

          addressModel.locality = currentLocation;
        });
      });

      MyAppState.selectedPosotion = addressModel;

      await hideProgress();

      pushAndRemoveUntil(
        context,
        ContainerScreen(user: MyAppState.currentUser),
        false,
      );
    } catch (e) {
      await hideProgress();
      _setPermissionMessage(
        'Failed to fetch current location. Please try again.',
      );
      log('[IOS_LOC] getCurrentPosition failed: $e');
    }
  }

  Future<void> _handleSetFromMap() async {
    _setPermissionMessage(null);
    log('[IOS_MAP] Set from map tapped');
    // #region agent log
    _appendRuntimeDebugLog(
      hypothesisId: 'H1',
      location: 'location_permission_screen:_handleSetFromMap:entry',
      message: 'Set from map tapped',
      data: {
        'isIOS': Platform.isIOS,
        'apiKeyPresent': GOOGLE_API_KEY.isNotEmpty,
        'apiKeyLength': GOOGLE_API_KEY.length,
        'isKeyFromFirestore': isGoogleApiKeyFromFirestore,
      },
    );
    // #endregion

    if (Platform.isIOS) {
      // #region agent log
      _appendRuntimeDebugLog(
        hypothesisId: 'H7',
        location: 'location_permission_screen:_handleSetFromMap:mapsKeyStatusStart',
        message: 'Requesting iOS maps key status from native',
        data: {
          'invoke': true,
        },
      );
      // #endregion
      try {
        final status = await _debugChannel.invokeMethod('mapsKeyStatus');
        if (status is Map) {
          // #region agent log
          _appendRuntimeDebugLog(
            hypothesisId: 'H7',
            location: 'location_permission_screen:_handleSetFromMap:mapsKeyStatus',
            message: 'Received iOS maps key status from native',
            data: {
              'length': status['length'],
              'isEmpty': status['isEmpty'],
              'didProvide': status['didProvide'],
            },
          );
          // #endregion
        }
      } catch (e) {
        // #region agent log
        _appendRuntimeDebugLog(
          hypothesisId: 'H7',
          location: 'location_permission_screen:_handleSetFromMap:mapsKeyStatusError',
          message: 'Failed to fetch iOS maps key status',
          data: {
            'error': e.toString(),
          },
        );
        // #endregion
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        final mapsStatusRaw = prefs.getString('debug.mapsKeyStatus');
        if (mapsStatusRaw != null) {
          final mapsStatus = jsonDecode(mapsStatusRaw) as Map<String, dynamic>;
          // #region agent log
          _appendRuntimeDebugLog(
            hypothesisId: 'H8',
            location:
                'location_permission_screen:_handleSetFromMap:mapsKeyStatusUserDefaults',
            message: 'Loaded iOS maps key status from UserDefaults',
            data: {
              'length': mapsStatus['length'],
              'isEmpty': mapsStatus['isEmpty'],
              'didProvide': mapsStatus['didProvide'],
            },
          );
          // #endregion
        } else {
          // #region agent log
          _appendRuntimeDebugLog(
            hypothesisId: 'H8',
            location:
                'location_permission_screen:_handleSetFromMap:mapsKeyStatusUserDefaultsMissing',
            message: 'iOS maps key status missing in UserDefaults',
            data: {
              'found': false,
            },
          );
          // #endregion
        }
      } catch (e) {
        // #region agent log
        _appendRuntimeDebugLog(
          hypothesisId: 'H8',
          location:
              'location_permission_screen:_handleSetFromMap:mapsKeyStatusUserDefaultsError',
          message: 'Failed to read iOS maps key status from UserDefaults',
          data: {
            'error': e.toString(),
          },
        );
        // #endregion
      }
      // #region agent log
      _appendRuntimeDebugLog(
        hypothesisId: 'H2',
        location: 'location_permission_screen:_handleSetFromMap:iosBranch',
        message: 'iOS branch before opening place picker',
        data: {
          'isIOS': true,
        },
      );
      // #endregion
      await _openPlacePicker();
      return;
    }

    checkPermission(() async {
      await showProgress(context, "Please wait...", false);
      try {
        await Geolocator.requestPermission();
        await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        await hideProgress();
        await _openPlacePicker();
      } catch (e) {
        await hideProgress();
        _setPermissionMessage(
          'Failed to access location. Please try again.',
        );
        log('[ANDROID_LOC] getCurrentPosition failed: $e');
      }
    });
  }

  Future<void> _openPlacePicker() async {
    AddressModel addressModel = AddressModel();
    String apiKeyToUse = GOOGLE_API_KEY;
    if (Platform.isIOS) {
      try {
        final iosKey = await _debugChannel.invokeMethod<String>('mapsApiKey');
        if (iosKey != null && iosKey.isNotEmpty) {
          apiKeyToUse = iosKey;
        }
        // #region agent log
        _appendRuntimeDebugLog(
          hypothesisId: 'H9',
          location: 'location_permission_screen:_openPlacePicker:apiKeySource',
          message: 'Selected API key for PlacePicker',
          data: {
            'isIOS': true,
            'usedIosKey': iosKey != null && apiKeyToUse == iosKey,
            'keyLength': apiKeyToUse.length,
          },
        );
        // #endregion
      } catch (e) {
        // #region agent log
        _appendRuntimeDebugLog(
          hypothesisId: 'H9',
          location: 'location_permission_screen:_openPlacePicker:apiKeySourceError',
          message: 'Failed to fetch iOS API key for PlacePicker',
          data: {
            'error': e.toString(),
          },
        );
        // #endregion
      }
    }
    // #region agent log
    _appendRuntimeDebugLog(
      hypothesisId: 'H3',
      location: 'location_permission_screen:_openPlacePicker:beforePush',
      message: 'Opening PlacePicker route',
      data: {
        'isIOS': Platform.isIOS,
        'apiKeyPresent': apiKeyToUse.isNotEmpty,
        'apiKeyLength': apiKeyToUse.length,
        'isKeyFromFirestore': isGoogleApiKeyFromFirestore,
      },
    );
    // #endregion
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlacePicker(
          apiKey: apiKeyToUse,
          onPlacePicked: (result) {
            // #region agent log
            _appendRuntimeDebugLog(
              hypothesisId: 'H4',
              location: 'location_permission_screen:_openPlacePicker:onPlacePicked',
              message: 'Place picked from PlacePicker',
              data: {
                'hasFormattedAddress': result.formattedAddress != null,
                'hasGeometry': result.geometry != null,
              },
            );
            // #endregion
            addressModel.locality = result.formattedAddress!.toString();

            addressModel.location = UserLocation(
              latitude: result.geometry!.location.lat,
              longitude: result.geometry!.location.lng,
            );

            log(result.toString());

            MyAppState.selectedPosotion = addressModel;

            setState(() {});

            pushAndRemoveUntil(
              context,
              ContainerScreen(user: MyAppState.currentUser),
              false,
            );
          },
          initialPosition: LatLng(-33.8567844, 151.213108),
          useCurrentLocation: !Platform.isIOS,
          selectInitialPosition: true,
          usePinPointingSearch: true,
          usePlaceDetailSearch: true,
          zoomGesturesEnabled: true,
          zoomControlsEnabled: true,
          resizeToAvoidBottomInset: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Image.asset("assets/images/location_screen.png"),
          ),
          Padding(
            padding:
                const EdgeInsets.only(left: 16, top: 32, right: 16, bottom: 8),
            child: Text(
              "Find restaurant and food near you",
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Color(COLOR_PRIMARY),
                  fontSize: 22.0,
                  fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "By allowing location access, you can search for restaurants and foods near you and receive more accurate delivery.",
              style: TextStyle(fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 40.0, left: 40.0, top: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: double.infinity),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(COLOR_PRIMARY),
                  padding: EdgeInsets.only(top: 12, bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25.0),
                    side: BorderSide(
                      color: Color(COLOR_PRIMARY),
                    ),
                  ),
                ),
                child: Text(
                  "Use current location",
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                onPressed: () {
                  if (Platform.isIOS) {
                    unawaited(_handleUseCurrentLocation());
                    return;
                  }
                  checkPermission(() async {
                    await showProgress(context, "Please wait...", false);

                    AddressModel addressModel = AddressModel();

                    try {
                      await Geolocator.requestPermission();

                      Position newLocalData =
                          await Geolocator.getCurrentPosition(
                              desiredAccuracy: LocationAccuracy.high);

                      await placemarkFromCoordinates(
                              newLocalData.latitude, newLocalData.longitude)
                          .then((valuePlaceMaker) {
                        Placemark placeMark = valuePlaceMaker[0];

                        setState(() {
                          addressModel.location = UserLocation(
                              latitude: newLocalData.latitude,
                              longitude: newLocalData.longitude);

                          String currentLocation =
                              "${placeMark.name}, ${placeMark.subLocality}, ${placeMark.locality}, ${placeMark.administrativeArea}, ${placeMark.postalCode}, ${placeMark.country}";

                          addressModel.locality = currentLocation;
                        });
                      });

                      setState(() {});

                      MyAppState.selectedPosotion = addressModel;

                      await hideProgress();

                      pushAndRemoveUntil(
                          context,
                          ContainerScreen(user: MyAppState.currentUser),
                          false);
                    } catch (e) {
                      await placemarkFromCoordinates(19.228825, 72.854118)
                          .then((valuePlaceMaker) {
                        Placemark placeMark = valuePlaceMaker[0];

                        setState(() {
                          addressModel.location = UserLocation(
                              latitude: 19.228825, longitude: 72.854118);

                          String currentLocation =
                              "${placeMark.name}, ${placeMark.subLocality}, ${placeMark.locality}, ${placeMark.administrativeArea}, ${placeMark.postalCode}, ${placeMark.country}";

                          addressModel.locality = currentLocation;
                        });
                      });

                      MyAppState.selectedPosotion = addressModel;

                      await hideProgress();

                      pushAndRemoveUntil(
                          context,
                          ContainerScreen(user: MyAppState.currentUser),
                          false);
                    }
                  });
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 40.0, left: 40.0, top: 10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: double.infinity),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(COLOR_PRIMARY),
                  padding: EdgeInsets.only(top: 12, bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25.0),
                    side: BorderSide(
                      color: Color(COLOR_PRIMARY),
                    ),
                  ),
                ),
                child: Text(
                  "Set from map",
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                onPressed: () async {
                  unawaited(_handleSetFromMap());
                },
              ),
            ),
          ),
          if (_permissionMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              child: SelectableText.rich(
                TextSpan(
                  text: _permissionMessage,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 13,
                  ),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          MyAppState.currentUser != null
              ? Padding(
                  padding:
                      const EdgeInsets.only(right: 40.0, left: 40.0, top: 10),
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(minWidth: double.infinity),
                    child: TextButton(
                      child: Text(
                        "Enter Address/Location",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white, // Text color set to white
                        ),
                      ),
                      onPressed: () async {
                        await Navigator.of(context)
                            .push(MaterialPageRoute(
                                builder: (context) => DeliveryAddressScreen()))
                            .then((value) {
                          if (value != null) {
                            AddressModel addressModel = value;
                            MyAppState.selectedPosotion = addressModel;
                            pushAndRemoveUntil(
                              context,
                              ContainerScreen(user: MyAppState.currentUser),
                              false,
                            );
                          }
                        });
                      },
                      style: ButtonStyle(
                        backgroundColor: MaterialStateProperty.all<Color>(
                          Color(
                              COLOR_PRIMARY), // Background color set to primary
                        ),
                        padding: MaterialStateProperty.all<EdgeInsetsGeometry>(
                          EdgeInsets.only(top: 12, bottom: 12),
                        ),
                        shape: MaterialStateProperty.all<OutlinedBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25.0),
                            side: BorderSide(
                              color: Color(COLOR_PRIMARY),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : Container()
        ],
      ),
    );
  }

  void checkPermission(Function() onTap) async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      _setPermissionMessage(
        'You have to allow location permission to use your location.',
      );
    } else if (permission == LocationPermission.deniedForever) {
      _setPermissionMessage(
        'Location permission is permanently denied. '
        'Please enable it in Settings.',
      );
      _showPermissionDialog();
    } else {
      onTap();
    }
  }
}
