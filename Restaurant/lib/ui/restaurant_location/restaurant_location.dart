// ignore_for_file: must_be_immutable

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:foodie_restaurant/main.dart';
import 'package:foodie_restaurant/model/VendorModel.dart';
import 'package:foodie_restaurant/services/FirebaseHelper.dart';
import 'package:foodie_restaurant/services/helper.dart';
import 'package:foodie_restaurant/ui/container/ContainerScreen.dart';
import 'package:foodie_restaurant/ui/ordersScreen/UnifiedOrdersScreen.dart';
import 'package:geoflutterfire2/geoflutterfire2.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:place_picker_v2/entities/location_result.dart';
import 'package:place_picker_v2/widgets/place_picker.dart';
import 'package:uuid/uuid.dart';

import '../../constants.dart';

class RestaurantLocationScreen extends StatefulWidget {
  final desc,
      phonenumber,
      filter,
      catid,
      restname,
      pic,
      deliveryChargeModel,
      cat;
  VendorModel? vendor;

  RestaurantLocationScreen(
      {Key? key,
      this.desc,
      this.phonenumber,
      this.catid,
      this.pic,
      this.filter,
      this.restname,
      this.vendor,
      this.cat,
      this.deliveryChargeModel})
      : super(key: key);

  @override
  _RestaurantLocationScreenState createState() =>
      _RestaurantLocationScreenState();
}

class _RestaurantLocationScreenState extends State<RestaurantLocationScreen> {
  var downloadUrl;
  final _formKey = GlobalKey<FormState>();
  var latValue = 0.0, longValue = 0.0;
  var query = "";

  ////current location

  VendorModel? vendor;
  AutovalidateMode _autoValidateMode = AutovalidateMode.disabled;

  var mapName = TextEditingController();
  var mapName1 = TextEditingController();
  var mapAddress = TextEditingController();
  var mapAddress1 = TextEditingController();
  var city = TextEditingController();
  var city1 = TextEditingController();
  var state = TextEditingController();
  var state1 = TextEditingController();
  final country = TextEditingController();
  final country1 = TextEditingController();

  var auth, authname, authpic;
  var add;

  @override
  void initState() {
    super.initState();
    auth = MyAppState.currentUser!.userID;
    authname = MyAppState.currentUser!.firstName;
    authpic = MyAppState.currentUser!.photos.isEmpty
        ? ' '
        : MyAppState.currentUser!.photos.first;

    if (widget.vendor != null) {
      add = widget.vendor!.location.split(',');
      mapName.text = add[0] == null ? "" : add[0];
      if (add.length > 0) {
        mapAddress.text = add[1] == null ? "" : add[1];
        if (add.length > 1) {
          city.text = add[2] == null ? "" : add[2];
          if (add.length > 2) {
            state.text = add[3] == null ? "" : add[3];
            if (add.length > 3) {
              country.text = add[4] == null ? "" : add[4];
            }
          }
        }
      }
      if (widget.vendor!.latitude != 0.0 && widget.vendor!.longitude != 0.0) {
        latValue = widget.vendor!.latitude;
        longValue = widget.vendor!.longitude;
      }
    }
  }

  LatLng get _mapCenter => LatLng(latValue, longValue);

  bool get _hasValidCoordinates =>
      latValue != 0.0 && longValue != 0.0;

  Set<Marker> get _markers {
    if (!_hasValidCoordinates) return {};
    return {
      Marker(
        markerId: const MarkerId('restaurant'),
        position: LatLng(latValue, longValue),
        infoWindow: InfoWindow(title: 'Restaurant'),
      ),
    };
  }

  @override
  void dispose() {
    mapName.dispose();
    mapAddress.dispose();
    city.dispose();
    state.dispose();
    country.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? Color(COLOR_DARK) : Color(0xFFFFFFFF),
      appBar: AppBar(
        title: Text('Restaurant Location'),
        centerTitle: false,
        iconTheme: IconThemeData(
            color: isDarkMode(context) ? Colors.white : Colors.black),
      ),
      body: SingleChildScrollView(
          child: Form(
              key: _formKey,
              autovalidateMode: _autoValidateMode,
              child: Padding(
                  padding: EdgeInsets.only(left: 20, right: 20, top: 20),
                  child: Column(children: [
                    Container(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          "Address",
                          style: TextStyle(
                              fontSize: 15,
                              fontFamily: "Poppinsl",
                              color: isDarkMode(context)
                                  ? Colors.white
                                  : Color(0Xff696A75)),
                        )),
                    Container(
                      padding: const EdgeInsetsDirectional.only(
                          start: 2, end: 20, bottom: 10),
                      child: TextFormField(
                          controller:
                              mapName1.text.isEmpty ? mapName : mapName1,
                          // widget.vendor == null ? mapName : null,
                          textAlignVertical: TextAlignVertical.center,
                          textInputAction: TextInputAction.next,
                          validator: validateEmptyField,

                          // onChanged: (text)=>  text=mapName.text ,
                          onSaved: (text) => mapName.text = text!,
                          style: TextStyle(fontSize: 18.0),
                          keyboardType: TextInputType.streetAddress,
                          cursorColor: Color(COLOR_PRIMARY),
                          // initialValue: widget.vendor == null
                          //     ? null
                          // : widget.vendor!.location.split(',')[0],
                          decoration: InputDecoration(
                            // contentPadding: EdgeInsets.symmetric(horizontal: 24),
                            hintText: 'Address',
                            hintStyle: TextStyle(
                                color: isDarkMode(context)
                                    ? Colors.white
                                    : Color(0Xff333333),
                                fontSize: 17,
                                fontFamily: "Poppinsm"),
                            focusedBorder: UnderlineInputBorder(
                              borderSide:
                                  BorderSide(color: Color(COLOR_PRIMARY)),
                            ),

                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Color(0XFFCCD6E2)),
                              // borderRadius: BorderRadius.circular(8.0),
                            ),
                          )),
                    ),
                    Container(
                        padding: EdgeInsets.only(top: 20),
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          "Apartment,suite,etc.",
                          style: TextStyle(
                              fontSize: 15,
                              fontFamily: "Poppinsl",
                              color: isDarkMode(context)
                                  ? Colors.white
                                  : Color(0Xff696A75)),
                        )),
                    Container(
                        padding: const EdgeInsetsDirectional.only(
                            start: 2, end: 20, bottom: 10),
                        child: TextFormField(
                            controller: mapAddress1.text.isEmpty
                                ? mapAddress
                                : mapAddress1,
                            // vendor == null ? mapAddress : null,
                            textAlignVertical: TextAlignVertical.center,
                            textInputAction: TextInputAction.next,
                            // validator: validateEmptyField,
                            onSaved: (text) => mapAddress.text = text!,
                            style: TextStyle(fontSize: 18.0),
                            keyboardType: TextInputType.streetAddress,
                            cursorColor: Color(COLOR_PRIMARY),
                            validator: validateEmptyField,
                            // initialValue: widget.vendor == null ? null : add[1],
                            // initialValue: MyAppState.currentUser!.shippingAddress.line1,
                            decoration: InputDecoration(
                              // contentPadding: EdgeInsets.symmetric(horizontal: 24),
                              hintText: 'Apartment,suite,etc.',
                              hintStyle: TextStyle(
                                  color: isDarkMode(context)
                                      ? Colors.white
                                      : Color(0Xff333333),
                                  fontSize: 17,
                                  fontFamily: "Poppinsm"),
                              focusedBorder: UnderlineInputBorder(
                                borderSide:
                                    BorderSide(color: Color(COLOR_PRIMARY)),
                              ),

                              enabledBorder: UnderlineInputBorder(
                                borderSide:
                                    BorderSide(color: Color(0XFFCCD6E2)),
                                // borderRadius: BorderRadius.circular(8.0),
                              ),
                            ))),
                    Container(
                        padding: EdgeInsets.only(top: 20),
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          "City",
                          style: TextStyle(
                              fontSize: 15,
                              fontFamily: "Poppinsl",
                              color: isDarkMode(context)
                                  ? Colors.white
                                  : Color(0Xff696A75)),
                        )),
                    Container(
                        padding: const EdgeInsetsDirectional.only(
                            start: 2, end: 20, bottom: 10),
                        child: TextFormField(
                            controller: city1.text.isEmpty ? city : city1,
                            textAlignVertical: TextAlignVertical.center,
                            textInputAction: TextInputAction.next,
                            // validator: validateEmptyField,
                            onSaved: (text) => city.text = text!,
                            style: TextStyle(fontSize: 18.0),
                            keyboardType: TextInputType.streetAddress,
                            cursorColor: Color(COLOR_PRIMARY),
                            validator: validateEmptyField,
                            // initialValue: widget.vendor == null ? null : add[2],
                            // initialValue: MyAppState.currentUser!.shippingAddress.line1,
                            decoration: InputDecoration(
                              // contentPadding: EdgeInsets.symmetric(horizontal: 24),
                              hintText: 'City',
                              hintStyle: TextStyle(
                                  color: isDarkMode(context)
                                      ? Colors.white
                                      : Color(0Xff333333),
                                  fontSize: 17,
                                  fontFamily: "Poppinsm"),
                              focusedBorder: UnderlineInputBorder(
                                borderSide:
                                    BorderSide(color: Color(COLOR_PRIMARY)),
                              ),

                              enabledBorder: UnderlineInputBorder(
                                borderSide:
                                    BorderSide(color: Color(0XFFCCD6E2)),
                                // borderRadius: BorderRadius.circular(8.0),
                              ),
                            ))),
                    Container(
                        padding: EdgeInsets.only(top: 20),
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          "State",
                          style: TextStyle(
                              fontSize: 15,
                              fontFamily: "Poppinsl",
                              color: isDarkMode(context)
                                  ? Colors.white
                                  : Color(0Xff696A75)),
                        )),
                    Container(
                        padding: const EdgeInsetsDirectional.only(
                            start: 2, end: 20, bottom: 10),
                        child: TextFormField(
                            controller: state1.text.isEmpty ? state : state1,
                            textAlignVertical: TextAlignVertical.center,
                            textInputAction: TextInputAction.next,
                            // validator: validateEmptyField,
                            onSaved: (text) => state.text = text!,
                            // initialValue: vendor == null ? null : add[3],
                            style: TextStyle(fontSize: 18.0),
                            keyboardType: TextInputType.streetAddress,
                            cursorColor: Color(COLOR_PRIMARY),
                            validator: validateEmptyField,
                            // initialValue: MyAppState.currentUser!.shippingAddress.line1,
                            decoration: InputDecoration(
                              // contentPadding: EdgeInsets.symmetric(horizontal: 24),
                              hintText: 'State',
                              hintStyle: TextStyle(
                                  color: isDarkMode(context)
                                      ? Colors.white
                                      : Color(0Xff333333),
                                  fontSize: 17,
                                  fontFamily: "Poppinsm"),
                              focusedBorder: UnderlineInputBorder(
                                borderSide:
                                    BorderSide(color: Color(COLOR_PRIMARY)),
                              ),

                              enabledBorder: UnderlineInputBorder(
                                borderSide:
                                    BorderSide(color: Color(0XFFCCD6E2)),
                                // borderRadius: BorderRadius.circular(8.0),
                              ),
                            ))),
                    Container(
                        padding: EdgeInsets.only(top: 20),
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          "Country",
                          style: TextStyle(
                              fontSize: 15,
                              fontFamily: "Poppinsl",
                              color: isDarkMode(context)
                                  ? Colors.white
                                  : Color(0Xff696A75)),
                        )),
                    Container(
                        padding: const EdgeInsetsDirectional.only(
                            start: 2, end: 20, bottom: 10),
                        child: TextFormField(
                            controller:
                                country1.text.isEmpty ? country : country1,
                            textAlignVertical: TextAlignVertical.center,
                            textInputAction: TextInputAction.next,
                            // initialValue: vendor == null ? null : add[4],
                            validator: validateEmptyField,
                            onSaved: (text) => country.text = text!,
                            style: TextStyle(fontSize: 18.0),
                            keyboardType: TextInputType.streetAddress,
                            cursorColor: Color(COLOR_PRIMARY),
                            // initialValue: MyAppState.currentUser!.shippingAddress.line1,
                            decoration: InputDecoration(
                              // contentPadding: EdgeInsets.symmetric(horizontal: 24),
                              hintText: 'Country',
                              hintStyle: TextStyle(
                                  color: isDarkMode(context)
                                      ? Colors.white
                                      : Color(0Xff333333),
                                  fontSize: 17,
                                  fontFamily: "Poppinsm"),
                              focusedBorder: UnderlineInputBorder(
                                borderSide:
                                    BorderSide(color: Color(COLOR_PRIMARY)),
                              ),

                              enabledBorder: UnderlineInputBorder(
                                borderSide:
                                    BorderSide(color: Color(0XFFCCD6E2)),
                                // borderRadius: BorderRadius.circular(8.0),
                              ),
                            ))),
                    Card(
                      child: ListTile(
                          leading: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ImageIcon(
                                AssetImage(
                                    'assets/images/current_location1.png'),
                                size: 23,
                                color: Color(COLOR_PRIMARY),
                              ),
                              // Icon(
                              //   Icons.location_searching_rounded,
                              //   color: Color(COLOR_PRIMARY),
                              // ),
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
                            // mapName.clear();
                            LocationResult? result = await Navigator.of(context)
                                .push(MaterialPageRoute(
                                    builder: (context) =>
                                        PlacePicker(GOOGLE_API_KEY)));
                            if (result != null) {
                              latValue = result.latLng!.latitude;
                              longValue = result.latLng!.longitude;

                              mapName1.text = result.name.toString();
                              mapAddress1.text = result
                                          .subLocalityLevel1!.name ==
                                      null
                                  ? result.subLocalityLevel2!.name.toString()
                                  : result.subLocalityLevel1!.name.toString();
                              city1.text = result.city!.name.toString();
                              state1.text =
                                  '${result.administrativeAreaLevel1!.name.toString()}';
                              country1.text =
                                  '${result.country!.name.toString()}';
                              setState(() {});
                            }
                          }),
                    ),
                    if (_hasValidCoordinates) ...[
                      SizedBox(height: 20),
                      Card(
                        elevation: 0.5,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            height: 220,
                            child: GoogleMap(
                              onMapCreated: (_) {},
                              initialCameraPosition: CameraPosition(
                                target: _mapCenter,
                                zoom: 14.0,
                              ),
                              markers: _markers,
                              myLocationEnabled: false,
                              zoomControlsEnabled: false,
                              mapType: MapType.normal,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ])))),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(20.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.only(top: 12, bottom: 12),
            backgroundColor: Color(COLOR_PRIMARY),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10.0),
              side: BorderSide(
                color: Color(COLOR_PRIMARY),
              ),
            ),
          ),
          onPressed: () {
            // #region agent log
            final vendorID = MyAppState.currentUser!.vendorID;
            final isNew = vendorID == '';
            final latLongZero = isNew
                ? (latValue == 0.0 && longValue == 0.0)
                : (widget.vendor!.latitude == 0.0 &&
                    widget.vendor!.longitude == 0.0);
            debugPrint(
                '[REST_SAVE] location button: isNew=$isNew '
                'latLongZero=$latLongZero lat=$latValue long=$longValue');
            // #endregion
            if (MyAppState.currentUser!.vendorID == '') {
              if (latValue == 0.0 && longValue == 0.0) {
                showDialog(
                        barrierDismissible: false,
                        context: context,
                        builder: (_) {
                          return AlertDialog(
                            content:
                                Text("selectLocationMovePinToLocation"),
                            actions: [
                              // FlatButton(
                              //   onPressed: () => Navigator.pop(
                              //       context, false), // passing false
                              //   child: Text('No'),
                              // ),
                              TextButton(
                                onPressed: () {
                                  hideProgress();
                                  Navigator.pop(context, true);
                                }, // passing true
                                child: Text('OK'),
                              ),
                            ],
                          );
                        });
              } else {
                addRestaurant();
              }
            } else {
              if (widget.vendor!.latitude == 0.0 &&
                  widget.vendor!.longitude == 0.0) {
                showDialog(
                    barrierDismissible: false,
                    context: context,
                    builder: (_) {
                      return AlertDialog(
                        content:
                            Text("selectLocationMovePinToLocation"),
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
                    });
              } else {
                updateRestaurant(add);
              }
            }
          },
          child: Text(
            MyAppState.currentUser!.vendorID == ''
                ? 'DONE'
                : 'UPDATE',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDarkMode(context) ? Colors.black : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  addRestaurant() async {
    final locationFormValid = _formKey.currentState?.validate() ?? false;
    // #region agent log
    debugPrint(
        '[REST_SAVE] addRestaurant: locationFormValid=$locationFormValid');
    // #endregion
    if (locationFormValid) {
      _formKey.currentState!.save();
      await showProgress(context, 'Adding Restaurant...', false);

      try {
        // #region agent log
        debugPrint('[REST_SAVE] addRestaurant: starting upload');
        // #endregion
        String downloadUrl = '';
        try {
          var uniqueID = Uuid().v4();
          Reference uploadRef = FirebaseStorage.instance
              .ref()
              .child('flutter/uberEats/productImages/$uniqueID.png');
          final metadata = SettableMetadata(contentType: 'image/png');
          UploadTask uploadTask = uploadRef.putFile(widget.pic, metadata);
          var taskSnapshot = await uploadTask.whenComplete(() {})
              .timeout(Duration(seconds: 90), onTimeout: () {
            throw TimeoutException(
                'Image upload timed out. Check network and try again.');
          });
          var storageRef = taskSnapshot.ref;
          downloadUrl = await storageRef.getDownloadURL()
              .timeout(Duration(seconds: 30), onTimeout: () {
            throw TimeoutException(
                'Getting image URL timed out. Check network and try again.');
          });
          // #region agent log
          debugPrint('[REST_SAVE] addRestaurant: upload done');
          // #endregion
        } catch (uploadError) {
          debugPrint(
              '[REST_SAVE] addRestaurant: upload failed, continuing without '
              'photo: $uploadError');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Photo upload failed. Restaurant will be saved without photo.',
                ),
              ),
            );
          }
        }
        GeoFirePoint myLocation =
          GeoFlutterFire().point(latitude: latValue, longitude: longValue);
      print("--->${widget.catid}");
      print("--->${widget.cat}");
      VendorModel vendors = VendorModel(
          author: auth,
          authorName: authname,
          authorProfilePic: authpic,
          categoryID: widget.catid,
          categoryTitle: widget.cat,
          createdAt: Timestamp.now(),
          geoFireData: GeoFireData(
              geohash: myLocation.hash,
              geoPoint: GeoPoint(latValue, longValue)),
          description: widget.desc,
          phonenumber: widget.phonenumber,
          filters: widget.filter,
          restStatus: true,
          latitude: latValue,
          longitude: longValue,
          specialDiscount:
              widget.vendor != null ? widget.vendor!.specialDiscount : [],
          specialDiscountEnable: widget.vendor != null
              ? widget.vendor!.specialDiscountEnable
              : false,
          location: mapName.text +
              "," +
              mapAddress.text +
              "," +
              city.text +
              "," +
              state.text +
              "," +
              country.text,
          photo: downloadUrl,
          workingHours:
              widget.vendor != null ? widget.vendor!.workingHours : [],
          deliveryCharge: widget.deliveryChargeModel,
          fcmToken: MyAppState.currentUser!.fcmToken,
          title: widget.restname);
        // #region agent log
        debugPrint(
            '[REST_SAVE] addRestaurant: calling firebaseCreateNewVendor');
        // #endregion
        await FireStoreUtils.firebaseCreateNewVendor(vendors)
            .timeout(Duration(seconds: 60), onTimeout: () {
          throw TimeoutException(
              'Saving restaurant timed out. Check network and try again.');
        });
        // #region agent log
        debugPrint(
            '[REST_SAVE] addRestaurant: firebaseCreateNewVendor done');
        // #endregion
        print('sending...');
        await hideProgress();
        showAlertDialog(this.context);
        return vendors;
      } catch (e, st) {
        // #region agent log
        debugPrint(
            '[REST_SAVE] addRestaurant: error e=$e st=${st.toString()}');
        // #endregion
        await hideProgress();
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('Error'),
              content: SelectableText(
                e.toString(),
                style: TextStyle(color: Colors.red),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    } else {
      setState(() {
        _autoValidateMode = AutovalidateMode.onUserInteraction;
      });
    }
  }

  updateRestaurant(add) async {
    print(mapName.text);
    final locationFormValid = _formKey.currentState?.validate() ?? false;
    // #region agent log
    debugPrint(
        '[REST_SAVE] updateRestaurant: locationFormValid=$locationFormValid');
    // #endregion
    if (locationFormValid) {
      _formKey.currentState!.save();
      await showProgress(context, 'Updating Restaurant...', false);
      query = mapName.text +
          "," +
          mapAddress.text +
          "," +
          city.text +
          "," +
          state.text +
          "," +
          country.text;
      print(query.toString() + "===LAAA");

      if (latValue != 0) {
        widget.vendor!.latitude = latValue;
      }
      if (longValue != 0) {
        widget.vendor!.longitude = longValue;
      }
      print("--->${widget.catid}");
      print("--->${widget.cat}");
      VendorModel vendors = VendorModel(
          id: MyAppState.currentUser!.vendorID,
          author: auth,
          authorName: authname,
          authorProfilePic: authpic,
          categoryID: widget.catid,
          categoryTitle: widget.cat,
          createdAt: Timestamp.now(),
          geoFireData: GeoFireData(
              geohash: GeoFlutterFire()
                  .point(
                      latitude: widget.vendor!.latitude,
                      longitude: widget.vendor!.longitude)
                  .hash,
              geoPoint:
                  GeoPoint(widget.vendor!.latitude, widget.vendor!.longitude)),
          description: widget.desc,
          phonenumber: widget.phonenumber,
          filters: widget.filter,
          location: mapName.text +
              "," +
              mapAddress.text +
              "," +
              city.text +
              "," +
              state.text +
              "," +
              country.text,
          latitude: widget.vendor!.latitude,
          longitude: widget.vendor!.longitude,
          photo: downloadUrl ?? widget.pic,
          restaurantCost: widget.vendor!.restaurantCost,
          openDineTime: widget.vendor!.openDineTime,
          closeDineTime: widget.vendor!.closeDineTime,
          restaurantMenuPhotos: widget.vendor!.restaurantMenuPhotos,
          enabledDiveInFuture: widget.vendor!.enabledDiveInFuture,
          deliveryCharge: widget.deliveryChargeModel,
          title: widget.restname,
          reviewsCount: widget.vendor!.reviewsCount,
          reviewsSum: widget.vendor!.reviewsSum,
          workingHours:
              widget.vendor != null ? widget.vendor!.workingHours : [],
          specialDiscount:
              widget.vendor != null ? widget.vendor!.specialDiscount : [],
          specialDiscountEnable: widget.vendor != null
              ? widget.vendor!.specialDiscountEnable
              : false,
          fcmToken: MyAppState.currentUser!.fcmToken);
      print(latValue.toString() + "===LAT");
      print(longValue.toString() + "===LONG");
      // #region agent log
      debugPrint('[REST_SAVE] updateRestaurant: calling updateVendor');
      // #endregion
      await FireStoreUtils.updateVendor(vendors);
      // #region agent log
      debugPrint('[REST_SAVE] updateRestaurant: updateVendor done');
      // #endregion
      print('sending...');
      await hideProgress();
      showUpdateDialog(this.context);
      return vendors;
    } else {
      setState(() {
        _autoValidateMode = AutovalidateMode.onUserInteraction;
      });
    }
  }

  showAlertDialog(BuildContext context) {
    // set up the button
    Widget okButton = TextButton(
      child: Text("OK"),
      onPressed: () {
        pushAndRemoveUntil(
            context,
            ContainerScreen(
              user: MyAppState.currentUser!,
              currentWidget: UnifiedOrdersScreen(),
              appBarTitle: 'Orders',
              drawerSelection: DrawerSelection.Orders,
            ),
            false);
      },
    );

    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: Text("Add Restaurant"),
      content: Text("Data is saved to database."),
      actions: [
        okButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  showUpdateDialog(BuildContext context) {
    // set up the button
    Widget okButton = TextButton(
      child: Text("OK"),
      onPressed: () {
        pushAndRemoveUntil(
            context,
            ContainerScreen(
              user: MyAppState.currentUser!,
              currentWidget: UnifiedOrdersScreen(),
              appBarTitle: 'Orders',
              drawerSelection: DrawerSelection.Orders,
            ),
            false);
      },
    );

    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: Text("Updating Restaurant"),
      content: Text("Data is updated in database."),
      actions: [
        okButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }
}
