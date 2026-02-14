import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:firebase_auth/firebase_auth.dart' as auth;

import 'package:flutter/cupertino.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:foodie_customer/common/common_elevated_button.dart';

import 'package:foodie_customer/constants.dart';

import 'package:foodie_customer/main.dart';

import 'package:foodie_customer/model/User.dart';

import 'package:foodie_customer/services/FirebaseHelper.dart';

import 'package:foodie_customer/services/helper.dart';

import 'package:foodie_customer/ui/container/ContainerScreen.dart';

import 'package:foodie_customer/ui/location_permission_screen.dart';
import 'package:foodie_customer/utils/extensions/context_extension.dart';

import 'package:image_picker/image_picker.dart';
import 'package:intl_phone_number_input/intl_phone_number_input.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:pin_code_fields/pin_code_fields.dart';

import '../../resources/colors.dart';

File? _image;

class PhoneNumberInputScreen extends StatefulWidget {
  final bool login;

  const PhoneNumberInputScreen({Key? key, required this.login})
      : super(key: key);

  @override
  _PhoneNumberInputScreenState createState() => _PhoneNumberInputScreenState();
}

class _PhoneNumberInputScreenState extends State<PhoneNumberInputScreen> {
  final ImagePicker _imagePicker = ImagePicker();

  TextEditingController _firstNameController = TextEditingController();

  TextEditingController _lastNameController = TextEditingController();

  GlobalKey<FormState> _key = GlobalKey();

  String? firstName, lastName, _phoneNumber, _verificationID, referralCode;

  bool _isPhoneValid = false, _codeSent = false;

  AutovalidateMode _validate = AutovalidateMode.disabled;
  String? _errorMessage;

  void _setErrorMessage(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid && !widget.login) {
      retrieveLostData();
    }

    return GestureDetector(
      onTap: context.dismissKeyboard,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16.0),
          child: new Form(
            key: _key,
            autovalidateMode: _validate,
            child: Column(
              children: <Widget>[
                new Align(
                  alignment: Directionality.of(context) == TextDirection.ltr
                      ? Alignment.topLeft
                      : Alignment.topRight,
                  child: Text(
                          widget.login
                              ? "Login with Phone Number"
                              : "Create new account",
                          style: TextStyle(
                              color: CustomColors.primary,
                              fontSize: 24.0,
                              fontWeight: FontWeight.w500))
                      ,
                ),

                /// user profile picture,  this is visible until we verify the

                /// code in case of sign up with phone number

                //Padding(

                //  padding: const EdgeInsets.only(

                //      left: 8.0, top: 32, right: 8, bottom: 8),

                //  child: Visibility(

                //    visible: !_codeSent && !widget.login,

                //    child: Stack(

                //      alignment: Alignment.bottomCenter,

                //      children: <Widget>[

                //        CircleAvatar(

                //          radius: 65,

                //          backgroundColor: Colors.grey.shade400,

                //          child: ClipOval(

                //            child: SizedBox(

                //              width: 170,

                //              height: 170,

                //              child: _image == null

                //                  ? Image.asset(

                //                      'assets/images/placeholder.jpg',

                //                      fit: BoxFit.cover,

                //                    )

                //                  : Image.file(

                //                      _image!,

                //                      fit: BoxFit.cover,

                //                    ),

                //            ),

                //          ),

                //        ),

                //        Positioned(

                //          left: 80,

                //          right: 0,

                //          child: FloatingActionButton(

                //            backgroundColor: Color(COLOR_ACCENT),

                //            child: Icon(

                //              CupertinoIcons.camera,

                //              color: isDarkMode(context)

                //                  ? Colors.black

                //                  : Colors.white,

                //            ),

                //            mini: true,

                //            onPressed: () => _onCameraClick(), // Corrected here

                //          ),

                //        )

                //      ],

                //    ),

                //  ),

                //),

                /// user first name text field , this is visible until we verify the

                /// code in case of sign up with phone number

                Visibility(
                  visible: !_codeSent && !widget.login,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: double.infinity),
                    child: TextFormField(
                      cursorColor: Color(COLOR_PRIMARY),
                      textAlignVertical: TextAlignVertical.center,
                      validator: (value) {
                        return validateName(value, true);
                      },
                      controller: _firstNameController,
                      onSaved: (String? val) {
                        firstName = val;
                      },
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        contentPadding: new EdgeInsets.symmetric(
                            vertical: 8, horizontal: 16),
                        fillColor: Colors.white,
                        hintText: "First Name",
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25.0),
                            borderSide: BorderSide(
                                color: Color(COLOR_PRIMARY), width: 2.0)),
                        errorBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.error),
                          borderRadius: BorderRadius.circular(25.0),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.error),
                          borderRadius: BorderRadius.circular(25.0),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(25.0),
                        ),
                      ),
                    ),
                  ),
                ),

                /// last name of the user , this is visible until we verify the

                /// code in case of sign up with phone number

                Visibility(
                  visible: !_codeSent && !widget.login,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: double.infinity),
                    child: Padding(
                      padding: const EdgeInsets.only(
                          top: 16.0, right: 8.0, left: 8.0),
                      child: TextFormField(
                        validator: (value) {
                          return validateName(value, false);
                        },
                        textAlignVertical: TextAlignVertical.center,
                        cursorColor: Color(COLOR_PRIMARY),
                        onSaved: (String? val) {
                          lastName = val;
                        },
                        controller: _lastNameController,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          contentPadding: new EdgeInsets.symmetric(
                              vertical: 8, horizontal: 16),
                          fillColor: Colors.white,
                          hintText: "Last Name",
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(25.0),
                              borderSide: BorderSide(
                                  color: Color(COLOR_PRIMARY), width: 2.0)),
                          errorBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.error),
                            borderRadius: BorderRadius.circular(25.0),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.error),
                            borderRadius: BorderRadius.circular(25.0),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(25.0),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                /// user phone number,  this is visible until we verify the code
                ///
                const SizedBox(height: 16.0),
                Visibility(
                  visible: !_codeSent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(25),
                        shape: BoxShape.rectangle,
                        border: Border.all(color: Colors.grey.shade200)),
                    child: InternationalPhoneNumberInput(
                      onInputChanged: (PhoneNumber number) =>
                          _phoneNumber = number.phoneNumber,

                      onInputValidated: (bool value) => _isPhoneValid = value,

                      ignoreBlank: true,

                      autoValidateMode: AutovalidateMode.onUserInteraction,

                      inputDecoration: InputDecoration(
                        hintText: 'Phone Number (+63)'
                            , // Updated hint to show PH prefix

                        border: const OutlineInputBorder(
                          borderSide: BorderSide.none,
                        ),

                        isDense: true,

                        errorBorder: const OutlineInputBorder(
                          borderSide: BorderSide.none,
                        ),
                      ),

                      inputBorder: const OutlineInputBorder(
                        borderSide: BorderSide.none,
                      ),

                      initialValue: PhoneNumber(
                          isoCode: 'PH'), // Default to the Philippines

                      selectorConfig: const SelectorConfig(
                        selectorType: PhoneInputSelectorType.DIALOG,
                      ),
                    ),
                  ),
                ),
                if ((_errorMessage ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12.0),
                    child: SelectableText.rich(
                      TextSpan(
                        text: _errorMessage,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 14.0,
                        ),
                      ),
                    ),
                  ),

                Visibility(
                  visible: !_codeSent && !widget.login,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: double.infinity),
                    child: Padding(
                      padding: const EdgeInsets.only(
                          top: 16.0, right: 8.0, left: 8.0),
                      child: TextFormField(
                        textAlignVertical: TextAlignVertical.center,
                        textInputAction: TextInputAction.next,
                        onSaved: (String? val) {
                          referralCode = val;
                        },
                        style: TextStyle(fontSize: 18.0),
                        cursorColor: Color(COLOR_PRIMARY),
                        decoration: InputDecoration(
                          contentPadding:
                              EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                          fillColor: Colors.white,
                          hintText: 'Referral Code (Optional)',
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(25.0),
                              borderSide: BorderSide(
                                  color: Color(COLOR_PRIMARY), width: 2.0)),
                          errorBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.error),
                            borderRadius: BorderRadius.circular(25.0),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.error),
                            borderRadius: BorderRadius.circular(25.0),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(25.0),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                /// code validation field, this is visible in case of sign up with

                /// phone number and the code is sent

                Visibility(
                  visible: _codeSent,
                  child: Padding(
                    padding:
                        EdgeInsets.only(top: 32.0, right: 24.0, left: 24.0),
                    child: PinCodeTextField(
                      length: 6,
                      appContext: context,
                      keyboardType: TextInputType.phone,
                      backgroundColor: Colors.transparent,
                      pinTheme: PinTheme(
                          shape: PinCodeFieldShape.box,
                          borderRadius: BorderRadius.circular(5),
                          fieldHeight: 40,
                          fieldWidth: 40,
                          activeColor: Color(COLOR_PRIMARY),
                          activeFillColor: isDarkMode(context)
                              ? Colors.grey.shade700
                              : Colors.grey.shade100,
                          selectedFillColor: Colors.transparent,
                          selectedColor: Color(COLOR_PRIMARY),
                          inactiveColor: Colors.grey.shade600,
                          inactiveFillColor: Colors.transparent),
                      enableActiveFill: true,
                      onCompleted: (v) {
                        _submitCode(v);
                      },
                      onChanged: (value) {
                        print(value);
                      },
                    ),
                  ),
                ),

                /// the main action button of the screen, this is hidden if we

                /// received the code from firebase

                /// the action and the title is base on the state,

                /// * Sign up with email and password: send email and password to

                /// firebase

                /// * Sign up with phone number: submits the phone number to

                /// firebase and await for code verification
                const SizedBox(height: 24.0),
                Visibility(
                    visible: !_codeSent,
                    child: SizedBox(
                      height: 50.0,
                      width: context.screenWidth,
                      child: CommonElevatedButton(
                        onButtonPressed: _signUp,
                        borderRadius: BorderRadius.circular(24.0),
                        text: "Send Code",
                        fontSize: 16.0,
                        fontWeight: FontWeight.w600,
                      ),
                    )),

                // Padding(
                //   padding: const EdgeInsets.all(32.0),
                //   child: Center(
                //     child: Text(
                //       "or",
                //       style: TextStyle(
                //           color: isDarkMode(context)
                //               ? Colors.white
                //               : Colors.black),
                //     ),
                //   ),
                // ),

                /// switch between sign up with phone number and email sign up states

                // InkWell(
                //   onTap: () {
                //     Navigator.pop(context);
                //   },
                //   child: Text(
                //     widget.login
                //         ? "Login with E-mail"
                //         : "Sign up with E-mail",
                //     style: TextStyle(
                //         color: Colors.lightBlue,
                //         fontWeight: FontWeight.bold,
                //         letterSpacing: 1),
                //   ),
                // )
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// submits the code to firebase to be validated, then get get the user

  /// object from firebase database

  /// @param code the code from input from code field

  /// creates a new user from phone login

  void _submitCode(String code) async {
    await showProgress(context,
        widget.login ? "Logging in..." : "Signing up...", false);

    try {
      if (_verificationID != null) {
        dynamic result = await FireStoreUtils.firebaseSubmitPhoneNumberCode(
            _verificationID!, code, _phoneNumber!, context,
            firstName: _firstNameController.text,
            lastName: _lastNameController.text,
            referralCode: referralCode ?? '');

        await hideProgress();

        if (result != null && result is User) {
          MyAppState.currentUser = result;

          pushAndRemoveUntil(context, ContainerScreen(user: result), false);

          if (MyAppState.currentUser!.active == true) {
            if (MyAppState.currentUser!.shippingAddress != null &&
                MyAppState.currentUser!.shippingAddress!.isNotEmpty) {
              if (MyAppState.currentUser!.shippingAddress!
                  .where((element) => element.isDefault == true)
                  .isNotEmpty) {
                MyAppState.selectedPosotion = MyAppState
                    .currentUser!.shippingAddress!
                    .where((element) => element.isDefault == true)
                    .single;
              } else {
                MyAppState.selectedPosotion =
                    MyAppState.currentUser!.shippingAddress!.first;
              }

              pushAndRemoveUntil(context, ContainerScreen(user: result), false);
            } else {
              pushAndRemoveUntil(context, LocationPermissionScreen(), false);
            }
          } else {
            showAlertDialog(
                context,
                "Your account has been disabled, Please contact to admin.",
                "",
                true);
          }
        } else if (result != null && result is String) {
          showAlertDialog(context, "failed", result, true);
        } else {
          showAlertDialog(context, "failed",
              "Couldn't create new user with phone number.", true);
        }
      } else {
        await hideProgress();
        _setErrorMessage("Couldn't get verification ID.");
      }
    } on auth.FirebaseAuthException catch (exception) {
      hideProgress();

      String message = "An error has occurred, please try again.";

      switch (exception.code) {
        case 'invalid-verification-code':
          message = "Invalid code or has been expired.";

          break;

        case 'user-disabled':
          message = "This user has been disabled.";

          break;

        default:
          message = "An error has occurred, please try again.";

          break;
      }
      _setErrorMessage(message);
    } catch (e, s) {
      print('_PhoneNumberInputScreenState._submitCode $e $s');

      hideProgress();
      _setErrorMessage("An error has occurred, please try again.");
    }
  }

  /// used on android by the image picker lib, sometimes on android the image

  /// is lost

  Future<void> retrieveLostData() async {
    final LostDataResponse? response = await _imagePicker.retrieveLostData();

    if (response == null) {
      return;
    }

    if (response.file != null) {
      setState(() {
        _image = File(response.file!.path);
      });
    }
  }

  //_signUp() async {

  //  if (_key.currentState?.validate() ?? false) {

  //    _key.currentState!.save();

  //    if (widget.login) {

  //      await _submitPhoneNumber(_phoneNumber!);

  //    } else {

  //      if (_isPhoneValid) {

  //        if (referralCode.toString().isNotEmpty) {

  //          FireStoreUtils.checkReferralCodeValidOrNot(referralCode.toString())

  //              .then((value) async {

  //            if (value == true) {

  //              await _submitPhoneNumber(_phoneNumber!);

  //            } else {

  //              final snack = SnackBar(

  //                content: Text(

  //                  'Referral Code is Invalid',

  //                  style: TextStyle(color: Colors.white),

  //                ),

  //                duration: Duration(seconds: 2),

  //                backgroundColor: Colors.black,

  //              );

  //              ScaffoldMessenger.of(context).showSnackBar(snack);

  //            }

  //          });

  //        } else {

  //          await _submitPhoneNumber(_phoneNumber!);

  //        }

  //      } else {

  //        ScaffoldMessenger.of(context).showSnackBar(SnackBar(

  //          content: Text("Invalid phone number, Please try again."),

  //        ));

  //      }

  //    }

  //  } else {

  //    setState(() {

  //      _validate = AutovalidateMode.onUserInteraction;

  //    });

  //  }

  //}

  _signUp() async {
    _setErrorMessage('');
    if (_key.currentState?.validate() ?? false) {
      _key.currentState!.save();

      if (widget.login) {
        await _submitPhoneNumber(_phoneNumber!);
      } else {
        if (_isPhoneValid) {
          await _submitPhoneNumber(_phoneNumber!);
        } else {
          _setErrorMessage("Invalid phone number, please try again.");
        }
      }
    } else {
      setState(() {
        _validate = AutovalidateMode.onUserInteraction;
      });
    }
  }

  _onCameraClick() {
    final action = CupertinoActionSheet(
      message: Text(
        'Add profile picture',
        style: TextStyle(fontSize: 15.0),
      ),
      actions: <Widget>[
        CupertinoActionSheetAction(
          child: Text('Choose from gallery'),
          isDefaultAction: false,
          onPressed: () async {
            Navigator.pop(context);
            await Future.delayed(const Duration(milliseconds: 300));
            if (!mounted) return;
            try {
              XFile? image =
                  await _imagePicker.pickImage(source: ImageSource.gallery);
              if (!mounted) return;
              if (image != null) {
                setState(() {
                  _image = File(image.path);
                });
              }
            } catch (e, s) {
              debugPrint('PhoneNumberInputScreen gallery picker: $e $s');
            }
          },
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        child: Text('cancel'),
        onPressed: () {
          Navigator.pop(context);
        },
      ),
    );

    showCupertinoModalPopup(context: context, builder: (context) => action);
  }

  /// sends a request to firebase to create a new user using phone number and

  /// navigate to [ContainerScreen] after wards

  _submitPhoneNumber(String phoneNumber) async {
    await showProgress(context, "Sending code...", true);

    await FireStoreUtils.firebaseSubmitPhoneNumber(
      phoneNumber,
      (String verificationId) {
        if (mounted) {
          hideProgress();
          _setErrorMessage(
            "Code verification timeout. Request a new code.",
          );

          setState(() {
            _codeSent = false;
          });
        }
      },
      (String? verificationId, int? forceResendingToken) {
        if (mounted) {
          hideProgress();

          _verificationID = verificationId;

          setState(() {
            _codeSent = true;
          });
        }
      },
      (auth.FirebaseAuthException error) {
        if (mounted) {
          hideProgress();

          print('--->${error.code}');

          print('${error.message} ${error.stackTrace}');

          String message = "An error has occurred, please try again.";

          switch (error.code) {
            case 'invalid-verification-code':
              message = "Invalid code or has been expired.";
              break;
            case 'user-disabled':
              message = "This user has been disabled.";
              break;
            case 'too-many-requests':
              message = "Too many attempts. Try again later.";
              break;
            case 'missing-client-identifier':
              message =
                  "Phone sign-in could not verify this app. Add your app's "
                  "SHA-1 and SHA-256 in Firebase Console (Project settings → "
                  "Your apps) and ensure Phone sign-in is enabled.";
              break;
            case 'invalid-phone-number':
              message = "Invalid phone number. Use country code (e.g. +1…).";
              break;
            default:
              message = "An error has occurred, please try again.";
              break;
          }
          _setErrorMessage(message);
        }
      },
      (auth.PhoneAuthCredential credential) async {
        if (mounted) {
          auth.UserCredential userCredential =
              await auth.FirebaseAuth.instance.signInWithCredential(credential);

          User? user = await FireStoreUtils.getCurrentUser(
              userCredential.user?.uid ?? '');

          if (user != null) {
            hideProgress();

            MyAppState.currentUser = user;

            if (MyAppState.currentUser!.shippingAddress != null &&
                MyAppState.currentUser!.shippingAddress!.isNotEmpty) {
              if (MyAppState.currentUser!.shippingAddress!
                  .where((element) => element.isDefault == true)
                  .isNotEmpty) {
                MyAppState.selectedPosotion = MyAppState
                    .currentUser!.shippingAddress!
                    .where((element) => element.isDefault == true)
                    .single;
              } else {
                MyAppState.selectedPosotion =
                    MyAppState.currentUser!.shippingAddress!.first;
              }

              pushAndRemoveUntil(context, ContainerScreen(user: user), false);
            } else {
              pushAndRemoveUntil(context, LocationPermissionScreen(), false);
            }
          } else {
            /// create a new user from phone login

            String profileImageUrl = '';

            if (_image != null) {
              File? compressedImage =
                  await FireStoreUtils.compressImage(_image!);

              final bytes = compressedImage?.readAsBytesSync().lengthInBytes;

              final kb = bytes ?? 0 / 1024;

              final mb = kb / 1024;

              if (mb > 2) {
                hideProgress();

                showAlertDialog(context, "error",
                    "Select an image that is less than 2MB", true);

                return;
              }

              profileImageUrl =
                  await FireStoreUtils.uploadUserImageToFireStorage(
                      compressedImage ?? _image!,
                      userCredential.user?.uid ?? '');
            }

            User user = User(
                firstName: _firstNameController.text,
                lastName: _lastNameController.text,
                fcmToken: '',
                phoneNumber: phoneNumber,
                active: true,
                role: USER_ROLE_CUSTOMER,
                lastOnlineTimestamp: Timestamp.now(),
                settings: UserSettings(),
                email: '',
                profilePictureURL: profileImageUrl,
                createdAt: Timestamp.now(),
                userID: userCredential.user?.uid ?? '');

            String? errorMessage = await FireStoreUtils.firebaseCreateNewUser(
                user, referralCode ?? '');

            hideProgress();

            if (errorMessage == null) {
              MyAppState.currentUser = user;
              unawaited(FireStoreUtils.refreshFcmTokenForUser(user));

              if (MyAppState.currentUser!.shippingAddress != null &&
                  MyAppState.currentUser!.shippingAddress!.isNotEmpty) {
                if (MyAppState.currentUser!.shippingAddress!
                    .where((element) => element.isDefault == true)
                    .isNotEmpty) {
                  MyAppState.selectedPosotion = MyAppState
                      .currentUser!.shippingAddress!
                      .where((element) => element.isDefault == true)
                      .single;
                } else {
                  MyAppState.selectedPosotion =
                      MyAppState.currentUser!.shippingAddress!.first;
                }

                pushAndRemoveUntil(context, ContainerScreen(user: user), false);
              } else {
                pushAndRemoveUntil(context, LocationPermissionScreen(), false);
              }
            } else {
              showAlertDialog(context, "failed",
                  "Couldn't create new user with phone number.", true);
            }
          }
        }
      },
    );
  }
}
