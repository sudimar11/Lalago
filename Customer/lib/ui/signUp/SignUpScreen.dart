import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/User.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/container/ContainerScreen.dart';
import 'package:foodie_customer/ui/location_permission_screen.dart';
import 'package:foodie_customer/ui/phoneAuth/PhoneNumberInputScreen.dart';
import 'package:foodie_customer/utils/extensions/context_extension.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl_phone_number_input/intl_phone_number_input.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../common/common_elevated_button.dart';
import '../../common/common_image.dart';
import '../../resources/assets.dart';
import '../../resources/colors.dart';

File? _image;
const Duration _debugIoTimeout = Duration(milliseconds: 150);
const String _debugLogPath =
    '/Users/sudimard/Documents/flutter_projects/LalaGo-Customer/.cursor/debug.log';
const String _debugFallbackFileName = 'cursor-debug.log';
const List<String> _debugLogEndpoints = <String>[
  'http://127.0.0.1:7242/ingest/9b9a1649-663c-43ba-aa17-deb0eb91410a',
  'http://localhost:7242/ingest/9b9a1649-663c-43ba-aa17-deb0eb91410a',
  'http://100.101.3.145:7242/ingest/9b9a1649-663c-43ba-aa17-deb0eb91410a',
  'http://Sudimars-MacBook-Air.local:7242/ingest/9b9a1649-663c-43ba-aa17-deb0eb91410a',
];
const String _runtimeDebugLogPath =
    '/Users/sudimard/Desktop/customer/.cursor/debug.log';
const String _runtimeDebugLogEndpoint =
    'http://127.0.0.1:7243/ingest/de1c04b0-9dd9-4425-b7d2-d38e14e33c57';

class _ExistingUserByPhone {
  const _ExistingUserByPhone({required this.docId, required this.data});
  final String docId;
  final Map<String, dynamic> data;
}

class SignUpScreen extends StatefulWidget {
  @override
  State createState() => _SignUpState();
}

class _SignUpState extends State<SignUpScreen> {
  static const MethodChannel _keychainChannel =
      MethodChannel('cursor.debug/keychain');
  bool _obscureText = true; // To control password visibility
  bool _obscureTextConfirm = true;

  // void _togglePasswordVisibility() {
  //   setState(() {
  //     _obscureText = !_obscureText;
  //     _obscureTextConfirm = !_obscureTextConfirm;

  //   });
  // }

  final ImagePicker _imagePicker = ImagePicker();

  TextEditingController _passwordController = TextEditingController();

  GlobalKey<FormState> _key = GlobalKey();

  String? firstName;
  String? lastName;
  String? email;
  String? mobile;
  String? password;
  String? confirmPassword;
  String? referralCode;

  AutovalidateMode _validate = AutovalidateMode.disabled;

  @override
  void initState() {
    super.initState();
    // #region agent log
    unawaited(_appendRuntimeDebugLog(
      hypothesisId: 'H0',
      location: 'SignUpScreen.initState',
      message: 'signup screen initialized',
      data: const <String, Object?>{
        'init': true,
      },
    ));
    // #endregion
  }

  Future<void> _appendDebugLog({
    required String hypothesisId,
    required String location,
    required String message,
    required Map<String, Object?> data,
    String runId = 'pre-fix',
  }) async {
    if (!kDebugMode) return;
    final payload = <String, Object?>{
      'sessionId': 'debug-session',
      'runId': runId,
      'hypothesisId': hypothesisId,
      'location': location,
      'message': message,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    try {
      await File(_debugLogPath).writeAsString(
        '${jsonEncode(payload)}\n',
        mode: FileMode.append,
      ).timeout(_debugIoTimeout);
    } catch (_) {
      for (final endpoint in _debugLogEndpoints) {
        try {
          final client = HttpClient();
          client.connectionTimeout = _debugIoTimeout;
          final request = await client
              .postUrl(Uri.parse(endpoint))
              .timeout(_debugIoTimeout);
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(payload));
          await request.close().timeout(_debugIoTimeout);
          client.close();
          break;
        } catch (_) {}
      }
    }
    try {
      final fallbackFile =
          File('${Directory.systemTemp.path}/$_debugFallbackFileName');
      await fallbackFile.writeAsString(
        '${jsonEncode(payload)}\n',
        mode: FileMode.append,
      ).timeout(_debugIoTimeout);
    } catch (_) {}
    try {
      final tempDir = await getTemporaryDirectory();
      final fallbackFile = File('${tempDir.path}/$_debugFallbackFileName');
      await fallbackFile.writeAsString(
        '${jsonEncode(payload)}\n',
        mode: FileMode.append,
      ).timeout(_debugIoTimeout);
    } catch (_) {}
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final fallbackFile = File('${docsDir.path}/$_debugFallbackFileName');
      await fallbackFile.writeAsString(
        '${jsonEncode(payload)}\n',
        mode: FileMode.append,
      ).timeout(_debugIoTimeout);
    } catch (_) {}
  }

  Future<void> _appendRuntimeDebugLog({
    required String hypothesisId,
    required String location,
    required String message,
    required Map<String, Object?> data,
    String runId = 'pre-fix',
  }) async {
    if (!kDebugMode) return;
    final payload = <String, Object?>{
      'sessionId': 'debug-session',
      'runId': runId,
      'hypothesisId': hypothesisId,
      'location': location,
      'message': message,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    try {
      await File(_runtimeDebugLogPath).writeAsString(
        '${jsonEncode(payload)}\n',
        mode: FileMode.append,
      ).timeout(_debugIoTimeout);
    } catch (_) {
      try {
        final client = HttpClient();
        client.connectionTimeout = _debugIoTimeout;
        final request = await client
            .postUrl(Uri.parse(_runtimeDebugLogEndpoint))
            .timeout(_debugIoTimeout);
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(payload));
        await request.close().timeout(_debugIoTimeout);
        client.close();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      retrieveLostData();
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SingleChildScrollView(
        child: Container(
          margin: EdgeInsets.only(left: 16.0, right: 16, bottom: 16),
          child: Form(
            key: _key,
            autovalidateMode: _validate,
            child: formUI(),
          ),
        ),
      ),
    );
  }

  Future<void> _onRegisterPressed() async {
    // #region agent log
    unawaited(_appendRuntimeDebugLog(
      hypothesisId: 'H0',
      location: 'SignUpScreen._onRegisterPressed',
      message: 'register button pressed',
      data: <String, Object?>{
        'hasEmail': (email ?? '').trim().isNotEmpty,
        'phoneLength': (mobile ?? '').trim().length,
      },
    ));
    // #endregion
    await _signUp();
  }

  Future<void> _logKeychainStatus() async {
    try {
      final result = await _keychainChannel.invokeMethod<dynamic>('check');
      final Map<String, Object?> data = result is Map
          ? result.map(
              (key, value) => MapEntry(key.toString(), value),
            )
          : <String, Object?>{};
      // #region agent log
      unawaited(_appendRuntimeDebugLog(
        hypothesisId: 'H8',
        location: 'SignUpScreen._logKeychainStatus',
        message: 'keychain add test result',
        data: <String, Object?>{
          'status': data['status'],
          'message': data['message'],
        },
      ));
      // #endregion
    } catch (e) {
      // #region agent log
      unawaited(_appendRuntimeDebugLog(
        hypothesisId: 'H8',
        location: 'SignUpScreen._logKeychainStatus:error',
        message: 'keychain check failed',
        data: <String, Object?>{
          'errorType': e.runtimeType.toString(),
        },
      ));
      // #endregion
    }
  }

  Future<void> _logBundleInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      // #region agent log
      unawaited(_appendRuntimeDebugLog(
        hypothesisId: 'H9',
        location: 'SignUpScreen._logBundleInfo',
        message: 'bundle info',
        data: <String, Object?>{
          'appName': info.appName,
          'packageName': info.packageName,
          'buildNumber': info.buildNumber,
          'version': info.version,
        },
      ));
      // #endregion
    } catch (e) {
      // #region agent log
      unawaited(_appendRuntimeDebugLog(
        hypothesisId: 'H9',
        location: 'SignUpScreen._logBundleInfo:error',
        message: 'bundle info failed',
        data: <String, Object?>{
          'errorType': e.runtimeType.toString(),
        },
      ));
      // #endregion
    }
  }

  Future<void> _logEntitlements() async {
    try {
      final result = await _keychainChannel.invokeMethod<dynamic>(
        'entitlements',
      );
      final Map<String, Object?> data = result is Map
          ? result.map(
              (key, value) => MapEntry(key.toString(), value),
            )
          : <String, Object?>{};
      // #region agent log
      unawaited(_appendRuntimeDebugLog(
        hypothesisId: 'H10',
        location: 'SignUpScreen._logEntitlements',
        message: 'entitlements snapshot',
        data: <String, Object?>{
          'taskKeychainGroups': data['task-keychain-access-groups'],
          'taskAppId': data['task-application-identifier'],
          'taskTeamId': data['task-team-identifier'],
          'signatureKeychainGroups': data['signature-keychain-access-groups'],
          'signatureAppId': data['signature-application-identifier'],
          'signatureTeamId': data['signature-team-identifier'],
          'signatureGetTaskAllow': data['signature-get-task-allow'],
          'taskError': data['task-error'],
          'signatureError': data['signature-error'],
          'signatureStatus': data['signature-status'],
          'signatureEntitlementCount': data['signature-entitlement-count'],
          'signatureKeys': data['signature-keys'],
        },
      ));
      // #endregion
    } catch (e) {
      // #region agent log
      unawaited(_appendRuntimeDebugLog(
        hypothesisId: 'H10',
        location: 'SignUpScreen._logEntitlements:error',
        message: 'entitlements fetch failed',
        data: <String, Object?>{
          'errorType': e.runtimeType.toString(),
        },
      ));
      // #endregion
    }
  }

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
              log('SignUpScreen gallery picker: $e $s');
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

  Widget formUI() {
    return Column(
      children: <Widget>[
        Align(
            alignment: Directionality.of(context) == TextDirection.ltr
                ? Alignment.topLeft
                : Alignment.topRight,
            child: Text(
              'Create new account',
              style: TextStyle(
                  color: Color(COLOR_PRIMARY),
                  fontWeight: FontWeight.bold,
                  fontSize: 25.0),
            )),
        const SizedBox(height: 16.0),
        Stack(
          alignment: Alignment.bottomCenter,
          children: <Widget>[
            CircleAvatar(
              radius: 65,
              backgroundColor: Colors.grey.shade400,
              child: ClipOval(
                child: SizedBox(
                  width: 170,
                  height: 170,
                  child: _image == null
                      ? Image.asset(
                          'assets/images/placeholder.jpg',
                          fit: BoxFit.cover,
                        )
                      : Image.file(
                          _image!,
                          fit: BoxFit.cover,
                        ),
                ),
              ),
            ),
            Positioned(
              left: 80,
              right: 0,
              child: FloatingActionButton(
                  backgroundColor: Color(COLOR_ACCENT),
                  child: Icon(
                    CupertinoIcons.camera,
                    color: isDarkMode(context) ? Colors.black : Colors.white,
                  ),
                  mini: true,
                  onPressed: _onCameraClick),
            )
          ],
        ),
        const SizedBox(height: 16.0),
        ConstrainedBox(
          constraints: BoxConstraints(minWidth: double.infinity),
          child: TextFormField(
            cursorColor: Color(COLOR_PRIMARY),
            textAlignVertical: TextAlignVertical.center,
            validator: (value) {
              return validateName(value, true);
            },
            onSaved: (String? val) {
              firstName = val;
            },
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              fillColor: Colors.white,
              hintText: 'First Name',
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25.0),
                  borderSide:
                      BorderSide(color: Color(COLOR_PRIMARY), width: 2.0)),
              errorBorder: OutlineInputBorder(
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.error),
                borderRadius: BorderRadius.circular(25.0),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.error),
                borderRadius: BorderRadius.circular(25.0),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(25.0),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16.0),
        ConstrainedBox(
          constraints: BoxConstraints(minWidth: double.infinity),
          child: TextFormField(
            validator: (value) {
              return validateName(value, false);
            },
            textAlignVertical: TextAlignVertical.center,
            cursorColor: Color(COLOR_PRIMARY),
            onSaved: (String? val) {
              lastName = val;
            },
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              fillColor: Colors.white,
              hintText: 'Last Name',
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25.0),
                  borderSide:
                      BorderSide(color: Color(COLOR_PRIMARY), width: 2.0)),
              errorBorder: OutlineInputBorder(
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.error),
                borderRadius: BorderRadius.circular(25.0),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.error),
                borderRadius: BorderRadius.circular(25.0),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(25.0),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16.0),
        ConstrainedBox(
          constraints: BoxConstraints(minWidth: double.infinity),
          child: TextFormField(
            keyboardType: TextInputType.emailAddress,
            textAlignVertical: TextAlignVertical.center,
            textInputAction: TextInputAction.next,
            cursorColor: Color(COLOR_PRIMARY),
            validator: validateEmail,
            onSaved: (String? val) {
              email = val;
            },
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              fillColor: Colors.white,
              hintText: 'Email Address',
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25.0),
                  borderSide:
                      BorderSide(color: Color(COLOR_PRIMARY), width: 2.0)),
              errorBorder: OutlineInputBorder(
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.error),
                borderRadius: BorderRadius.circular(25.0),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.error),
                borderRadius: BorderRadius.circular(25.0),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(25.0),
              ),
            ),
          ),
        ),

        /// user mobile text field, this is hidden in case of sign up with

        /// phone number
        const SizedBox(height: 16.0),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            shape: BoxShape.rectangle,
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: InternationalPhoneNumberInput(
            onInputChanged: (PhoneNumber number) => mobile = number.phoneNumber,

            ignoreBlank: true,

            autoValidateMode: AutovalidateMode.onUserInteraction,

            inputDecoration: InputDecoration(
              hintText: 'Phone Number',
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

            initialValue:
                PhoneNumber(isoCode: 'PH'), // Set default to the Philippines

            selectorConfig: const SelectorConfig(
              selectorType: PhoneInputSelectorType.DIALOG,
            ),
          ),
        ),
        const SizedBox(height: 16.0),
        ConstrainedBox(
          constraints: BoxConstraints(minWidth: double.infinity),
          child: TextFormField(
            obscureText: _obscureText, // Use the visibility state variable

            textAlignVertical: TextAlignVertical.center,

            textInputAction: TextInputAction.next,

            controller: _passwordController,

            validator: validatePassword,

            onSaved: (String? val) {
              password = val;
            },

            style: TextStyle(fontSize: 18.0),

            cursorColor: Color(COLOR_PRIMARY),

            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              fillColor: Colors.white,
              hintText: 'Password',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureText ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () {
                  setState(() {
                    _obscureText = !_obscureText; // Toggle visibility
                  });
                },
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25.0),
                borderSide: BorderSide(color: Color(COLOR_PRIMARY), width: 2.0),
              ),
              errorBorder: OutlineInputBorder(
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.error),
                borderRadius: BorderRadius.circular(25.0),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.error),
                borderRadius: BorderRadius.circular(25.0),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(25.0),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16.0),
        ConstrainedBox(
          constraints: BoxConstraints(minWidth: double.infinity),
          child: TextFormField(
            textAlignVertical: TextAlignVertical.center,

            textInputAction: TextInputAction.done,

            onFieldSubmitted: (_) => _signUp(),

            obscureText:
                _obscureTextConfirm, // Use the visibility state variable

            validator: (val) =>
                validateConfirmPassword(_passwordController.text, val),

            onSaved: (String? val) {
              confirmPassword = val;
            },

            style: TextStyle(fontSize: 18.0),

            cursorColor: Color(COLOR_PRIMARY),

            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              fillColor: Colors.white,
              hintText: 'Confirm Password',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureTextConfirm ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () {
                  setState(() {
                    _obscureTextConfirm =
                        !_obscureTextConfirm; // Toggle visibility
                  });
                },
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25.0),
                borderSide: BorderSide(color: Color(COLOR_PRIMARY), width: 2.0),
              ),
              errorBorder: OutlineInputBorder(
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.error),
                borderRadius: BorderRadius.circular(25.0),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.error),
                borderRadius: BorderRadius.circular(25.0),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(25.0),
              ),
            ),
          ),
        ),

        //ConstrainedBox(

        //  constraints: BoxConstraints(minWidth: double.infinity),
        const SizedBox(height: 16.0),
        ConstrainedBox(
          constraints: BoxConstraints(minWidth: double.infinity),
          child: TextFormField(
            textAlignVertical: TextAlignVertical.center,
            textInputAction: TextInputAction.next,
            onSaved: (String? val) {
              referralCode = val;
            },
            style: TextStyle(fontSize: 18.0),
            cursorColor: Color(COLOR_PRIMARY),
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              fillColor: Colors.white,
              hintText: 'Referral Code (Optional)',
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25.0),
                  borderSide:
                      BorderSide(color: Color(COLOR_PRIMARY), width: 2.0)),
              errorBorder: OutlineInputBorder(
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.error),
                borderRadius: BorderRadius.circular(25.0),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.error),
                borderRadius: BorderRadius.circular(25.0),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(25.0),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24.0),
        SizedBox(
          height: 50.0,
          width: context.screenWidth,
          child: CommonElevatedButton(
            onButtonPressed: _onRegisterPressed,
            borderRadius: BorderRadius.circular(24.0),
            text: "Register",
            fontColor: Colors.white,
            fontSize: 16.0,
            fontWeight: FontWeight.w600,
          ),
        ),

        const SizedBox(height: 16.0),
        Row(
          spacing: 8.0,
          children: [
            Expanded(
              child: Divider(
                color: Colors.grey.shade300,
                thickness: 0.5,
              ),
            ),
            Text("Or"),
            Expanded(
              child: Divider(
                color: Colors.grey.shade300,
                thickness: 0.5,
              ),
            )
          ],
        ),
        const SizedBox(height: 24.0),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildSignUpOption(
              onTap: _signUpWithGoogle,
              icon: CommonImage(
                path: Assets.google,
                height: 24.0,
                width: 24.0,
              ),
              label: "Google",
              backgroundColor: Colors.white,
              borderColor: Colors.grey.shade300,
            ),
            _buildSignUpOption(
              onTap: _signUpWithApple,
              icon: Icon(
                Icons.apple,
                size: 28.0,
                color: isDarkMode(context)
                    ? Colors.white
                    : Colors.black,
              ),
              label: "Apple",
              backgroundColor: isDarkMode(context)
                  ? Colors.black
                  : Colors.white,
              borderColor: isDarkMode(context)
                  ? Colors.grey.shade700
                  : Colors.grey.shade300,
            ),
            _buildSignUpOption(
              onTap: () =>
                  push(context, PhoneNumberInputScreen(login: false)),
              icon: CommonImage(
                path: Assets.icPhoneCall,
                height: 24.0,
                width: 24.0,
              ),
              label: "Phone",
              backgroundColor: CustomColors.primary,
              borderColor: CustomColors.primary,
              iconColor: Colors.white,
            ),
          ],
        ),
        const SizedBox(height: 36.0),
        //Padding(

        //  padding: const EdgeInsets.all(32.0),

        //  child: Center(

        //    child: Text(

        //      'or',

        //      style: TextStyle(

        //          color: isDarkMode(context) ? Colors.white : Colors.black),

        //    ),

        //  ),

        //),

        //InkWell(

        //  onTap: () {

        //    push(context, PhoneNumberInputScreen(login: false));

        //  },

        //  child: Padding(

        //    padding: EdgeInsets.only(top: 10, right: 40, left: 40),

        //    child: Container(

        //      alignment: Alignment.bottomCenter,

        //      padding: EdgeInsets.all(5),

        //      decoration: BoxDecoration(

        //          borderRadius: BorderRadius.circular(25),

        //          border: Border.all(color: Color(COLOR_PRIMARY), width: 1)),

        //      child: Row(

        //        mainAxisAlignment: MainAxisAlignment.spaceEvenly,

        //        children: [

        //          Icon(

        //            Icons.phone,

        //            color: Color(COLOR_PRIMARY),

        //          ),

        //          Flexible(

        //            // Allow Text to shrink if needed

        //            child: Text(

        //              "Sign Up With Phone Number",

        //              style: TextStyle(

        //                  color: Color(COLOR_PRIMARY),

        //                  fontWeight: FontWeight.bold,

        //                  letterSpacing: 1),

        //              overflow: TextOverflow.ellipsis, // Prevent overflow

        //            ),

        //          ),

        //        ],

        //      ),

        //    ),

        //  ),

        //)
      ],
    );
  }

  /// dispose text controllers to avoid memory leaks

  @override
  void dispose() {
    _passwordController.dispose();

    _image = null;

    super.dispose();
  }

  /// if the fields are validated and location is enabled we create a new user

  /// and navigate to [ContainerScreen] else we show error

  _signUp() async {
    // #region agent log
    unawaited(_appendRuntimeDebugLog(
      hypothesisId: 'H1',
      location: 'SignUpScreen._signUp:entry',
      message: 'signup tap received',
      data: <String, Object?>{
        'hasEmail': (email ?? '').trim().isNotEmpty,
        'emailLength': (email ?? '').trim().length,
        'phoneLength': (mobile ?? '').trim().length,
        'hasImage': _image != null,
        'hasReferral': (referralCode ?? '').trim().isNotEmpty,
      },
    ));
    // #endregion
    // #region agent log
    unawaited(_appendRuntimeDebugLog(
      hypothesisId: 'H1',
      location: 'SignUpScreen._signUp:beforeValidate',
      message: 'starting form validation',
      data: const <String, Object?>{
        'start': true,
      },
    ));
    // #endregion
    bool isValid = false;
    try {
      isValid = _key.currentState?.validate() ?? false;
    } catch (e) {
      // #region agent log
      unawaited(_appendRuntimeDebugLog(
        hypothesisId: 'H1',
        location: 'SignUpScreen._signUp:validateError',
        message: 'form validation threw',
        data: <String, Object?>{
          'errorType': e.runtimeType.toString(),
        },
      ));
      // #endregion
      rethrow;
    }
    // #region agent log
    unawaited(_appendRuntimeDebugLog(
      hypothesisId: 'H1',
      location: 'SignUpScreen._signUp:afterValidate',
      message: 'form validation completed',
      data: <String, Object?>{
        'isValid': isValid,
      },
    ));
    // #endregion
    // #region agent log
    unawaited(_appendRuntimeDebugLog(
      hypothesisId: 'H1',
      location: 'SignUpScreen._signUp:beforeLegacyLogValidate',
      message: 'calling legacy debug log validate',
      data: const <String, Object?>{
        'stage': 'validate',
      },
    ));
    // #endregion
    // #region agent log
    unawaited(_appendDebugLog(
      hypothesisId: 'H1',
      location: 'SignUpScreen._signUp:validate',
      message: 'signup form validation result',
      data: <String, Object?>{
        'isValid': isValid,
        'platform': Platform.operatingSystem,
      },
    ));
    // #endregion
    // #region agent log
    unawaited(_appendRuntimeDebugLog(
      hypothesisId: 'H1',
      location: 'SignUpScreen._signUp:afterLegacyLogValidate',
      message: 'legacy debug log validate completed',
      data: const <String, Object?>{
        'stage': 'validate',
      },
    ));
    // #endregion

    if (isValid) {
      try {
        _key.currentState!.save();
      } catch (e) {
        // #region agent log
        unawaited(_appendRuntimeDebugLog(
          hypothesisId: 'H1',
          location: 'SignUpScreen._signUp:saveError',
          message: 'form save threw',
          data: <String, Object?>{
            'errorType': e.runtimeType.toString(),
          },
        ));
        // #endregion
        rethrow;
      }
      // #region agent log
      unawaited(_appendRuntimeDebugLog(
        hypothesisId: 'H1',
        location: 'SignUpScreen._signUp:afterSave',
        message: 'form save completed',
        data: <String, Object?>{
          'emailLength': (email ?? '').trim().length,
          'phoneLength': (mobile ?? '').trim().length,
        },
      ));
      // #endregion

      // #region agent log
      unawaited(_appendRuntimeDebugLog(
        hypothesisId: 'H1',
        location: 'SignUpScreen._signUp:beforeLegacyLogSave',
        message: 'calling legacy debug log save',
        data: const <String, Object?>{
          'stage': 'save',
        },
      ));
      // #endregion
      // #region agent log
      unawaited(_appendDebugLog(
        hypothesisId: 'H1',
        location: 'SignUpScreen._signUp:save',
        message: 'signup form saved values',
        data: <String, Object?>{
          'hasEmail': (email ?? '').trim().isNotEmpty,
          'emailLength': (email ?? '').trim().length,
          'phoneLength': (mobile ?? '').trim().length,
          'hasImage': _image != null,
          'hasReferral': (referralCode ?? '').trim().isNotEmpty,
        },
      ));
      // #endregion
      // #region agent log
      unawaited(_appendRuntimeDebugLog(
        hypothesisId: 'H1',
        location: 'SignUpScreen._signUp:afterLegacyLogSave',
        message: 'legacy debug log save completed',
        data: const <String, Object?>{
          'stage': 'save',
        },
      ));
      // #endregion

      await showProgress(
        context,
        "Creating new account, Please wait...",
        false,
      );

      // Check for duplicate phone number before proceeding
      // #region agent log
      unawaited(_appendRuntimeDebugLog(
        hypothesisId: 'H2',
        location: 'SignUpScreen._signUp:beforePhoneCheck',
        message: 'starting phone check',
        data: <String, Object?>{
          'phoneLength': (mobile ?? '').trim().length,
        },
      ));
      // #endregion
      final phoneCheckStopwatch = kDebugMode ? (Stopwatch()..start()) : null;
      final existingByPhone = await _getExistingUserByPhone(mobile?.trim());
      if (phoneCheckStopwatch != null) {
        phoneCheckStopwatch.stop();
        log(
          '[SIGNUP_TIMING] phoneCheckMs=${phoneCheckStopwatch.elapsedMilliseconds}',
        );
      }
      // #region agent log
      unawaited(_appendRuntimeDebugLog(
        hypothesisId: 'H2',
        location: 'SignUpScreen._signUp:phoneCheck',
        message: 'phone check result',
        data: <String, Object?>{
          'phoneLength': (mobile ?? '').trim().length,
          'hasExisting': existingByPhone != null,
        },
      ));
      // #endregion

      if (kDebugMode) {
        unawaited(_logBundleInfo());
        unawaited(_logEntitlements());
        unawaited(_logKeychainStatus());
      }
      await _signUpWithEmailAndPassword(
        existingUserDocId: existingByPhone?.docId,
        existingUserData: existingByPhone?.data,
      );
      // #region agent log
      unawaited(_appendRuntimeDebugLog(
        hypothesisId: 'H2',
        location: 'SignUpScreen._signUp:signupComplete',
        message: 'signup flow completed',
        data: const <String, Object?>{
          'completed': true,
        },
      ));
      // #endregion
    } else {
      // #region agent log
      unawaited(_appendRuntimeDebugLog(
        hypothesisId: 'H1',
        location: 'SignUpScreen._signUp:invalid',
        message: 'form validation failed',
        data: <String, Object?>{
          'isValid': false,
        },
      ));
      // #endregion
      setState(() {
        _validate = AutovalidateMode.onUserInteraction;
      });
    }
  }

  /// Returns existing user doc by exact phone number, or null if none.
  Future<_ExistingUserByPhone?> _getExistingUserByPhone(String? phone) async {
    if (phone == null || phone.isEmpty) return null;
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection(USERS)
          .where('phoneNumber', isEqualTo: phone)
          .limit(1)
          .get();
      if (querySnapshot.docs.isEmpty) return null;
      final doc = querySnapshot.docs.first;
      final data = doc.data();
      if (data.isEmpty) return null;
      return _ExistingUserByPhone(docId: doc.id, data: data);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isPhoneNumberTaken(String? phone) async {
    if (phone == null || phone.isEmpty) return false;
    try {
      // #region agent log
      unawaited(_appendRuntimeDebugLog(
        hypothesisId: 'H2',
        location: 'SignUpScreen._isPhoneNumberTaken:entry',
        message: 'phone check started',
        data: <String, Object?>{
          'phoneLength': phone.trim().length,
        },
      ));
      // #endregion
      // #region agent log
      unawaited(_appendRuntimeDebugLog(
        hypothesisId: 'H2',
        location: 'SignUpScreen._isPhoneNumberTaken:beforeLegacyLog',
        message: 'calling legacy debug log phone check',
        data: const <String, Object?>{
          'stage': 'phoneCheck',
        },
      ));
      // #endregion
      // #region agent log
      unawaited(_appendDebugLog(
        hypothesisId: 'H3',
        location: 'SignUpScreen._isPhoneNumberTaken:query',
        message: 'checking phone number duplication',
        data: <String, Object?>{
          'phoneLength': phone.trim().length,
        },
      ));
      // #endregion
      // #region agent log
      unawaited(_appendRuntimeDebugLog(
        hypothesisId: 'H2',
        location: 'SignUpScreen._isPhoneNumberTaken:afterLegacyLog',
        message: 'legacy debug log phone check completed',
        data: const <String, Object?>{
          'stage': 'phoneCheck',
        },
      ));
      // #endregion

      final querySnapshot = await FirebaseFirestore.instance
          .collection(USERS)
          .where('phoneNumber', isEqualTo: phone)
          .limit(1)
          .get();
      // #region agent log
      unawaited(_appendRuntimeDebugLog(
        hypothesisId: 'H2',
        location: 'SignUpScreen._isPhoneNumberTaken:beforeLegacyLogResult',
        message: 'calling legacy debug log phone result',
        data: const <String, Object?>{
          'stage': 'phoneResult',
        },
      ));
      // #endregion
      // #region agent log
      unawaited(_appendDebugLog(
        hypothesisId: 'H3',
        location: 'SignUpScreen._isPhoneNumberTaken:result',
        message: 'phone number duplication result',
        data: <String, Object?>{
          'isTaken': querySnapshot.docs.isNotEmpty,
        },
      ));
      // #endregion
      // #region agent log
      unawaited(_appendRuntimeDebugLog(
        hypothesisId: 'H2',
        location: 'SignUpScreen._isPhoneNumberTaken:afterLegacyLogResult',
        message: 'legacy debug log phone result completed',
        data: const <String, Object?>{
          'stage': 'phoneResult',
        },
      ));
      // #endregion
      final isTaken = querySnapshot.docs.isNotEmpty;
      // #region agent log
      unawaited(_appendRuntimeDebugLog(
        hypothesisId: 'H2',
        location: 'SignUpScreen._isPhoneNumberTaken:result',
        message: 'phone check finished',
        data: <String, Object?>{
          'isTaken': isTaken,
        },
      ));
      // #endregion
      return isTaken;
    } catch (e) {
      // #region agent log
      unawaited(_appendRuntimeDebugLog(
        hypothesisId: 'H2',
        location: 'SignUpScreen._isPhoneNumberTaken:error',
        message: 'phone check failed',
        data: <String, Object?>{
          'errorType': e.runtimeType.toString(),
        },
      ));
      // #endregion
      return false;
    }
  }

  _signUpWithEmailAndPassword({
    String? existingUserDocId,
    Map<String, dynamic>? existingUserData,
  }) async {
    log(
      'signup start email=${email?.trim()} '
      'phone=${mobile?.trim()} '
      'hasImage=${_image != null} '
      'hasReferral=${referralCode?.trim().isNotEmpty == true} '
      'platform=${Platform.operatingSystem}',
    );
    // #region agent log
    unawaited(_appendDebugLog(
      hypothesisId: 'H2',
      location: 'SignUpScreen._signUpWithEmailAndPassword:start',
      message: 'calling firebase signup',
      data: <String, Object?>{
        'emailLength': (email ?? '').trim().length,
        'phoneLength': (mobile ?? '').trim().length,
        'hasImage': _image != null,
        'hasReferral': (referralCode ?? '').trim().isNotEmpty,
        'platform': Platform.operatingSystem,
      },
    ));
    // #endregion

    dynamic result = await FireStoreUtils.firebaseSignUpWithEmailAndPassword(
      emailAddress: email?.trim() ?? "",
      password: password?.trim() ?? "",
      image: _image,
      firstName: firstName ?? "",
      lastName: lastName ?? "",
      mobile: mobile ?? "",
      context: context,
      referralCode: (referralCode ?? '').trim(),
      existingUserDocId: existingUserDocId,
      existingUserData: existingUserData,
    );
    log('signup result type=${result.runtimeType} value=$result');
    // #region agent log
    unawaited(_appendDebugLog(
      hypothesisId: 'H2',
      location: 'SignUpScreen._signUpWithEmailAndPassword:result',
      message: 'firebase signup result received',
      data: <String, Object?>{
        'resultType': result.runtimeType.toString(),
        'isUser': result is User,
        'isString': result is String,
        'isNull': result == null,
      },
    ));
    // #endregion

    await hideProgress();

    if (result != null && result is User) {
      MyAppState.currentUser = result;

      if (MyAppState.currentUser!.shippingAddress != null &&
          MyAppState.currentUser!.shippingAddress!.isNotEmpty) {
        if (MyAppState.currentUser!.shippingAddress!
            .where((element) => element.isDefault == true)
            .isNotEmpty) {
          MyAppState.selectedPosotion = MyAppState.currentUser!.shippingAddress!
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
    } else if (result != null && result is String) {
      log('[REGISTER_ERROR] $result');
      showAlertDialog(context, 'failed', result, true);
    } else {
      log('[REGISTER_ERROR] unknown signup failure result=$result');
      showAlertDialog(context, 'failed', "Couldn't sign up", true);
    }
  }

  _signUpWithGoogle() async {
    await showProgress(context, "Signing up, please wait...", false);
    bool hadError = false;
    dynamic result;
    try {
      result = await FireStoreUtils.loginWithGoogle();
    } catch (e, s) {
      hadError = true;
      log('_SignUpScreen._signUpWithGoogle $e $s');
    } finally {
      try {
        await hideProgress();
      } catch (_) {}
    }

    if (!mounted) return;

    if (hadError) {
      showAlertDialog(
          context, 'error', "Couldn't sign up with google.", true);
      return;
    }

    if (result != null && result is User) {
      MyAppState.currentUser = result;

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
      showAlertDialog(context, 'error', result, true);
    } else {
      showAlertDialog(
          context, 'error', "Couldn't sign up with google.", true);
    }
  }

  _signUpWithApple() async {
    await showProgress(context, "Signing up, please wait...", false);
    bool hadError = false;
    dynamic result;
    try {
      result = await FireStoreUtils.loginWithApple();
    } catch (e, s) {
      hadError = true;
      log('_SignUpScreen._signUpWithApple $e $s');
    } finally {
      try {
        await hideProgress();
      } catch (_) {}
    }

    if (!mounted) return;

    if (hadError) {
      showAlertDialog(
          context, 'error', "Couldn't sign up with Apple.", true);
      return;
    }

    if (result != null && result is User) {
      MyAppState.currentUser = result;

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
      showAlertDialog(context, 'error', result, true);
    } else {
      showAlertDialog(
          context, 'error', "Couldn't sign up with Apple.", true);
    }
  }

  Widget _buildSignUpOption({
    required VoidCallback onTap,
    required Widget icon,
    required String label,
    required Color backgroundColor,
    required Color borderColor,
    Color? iconColor,
  }) {
    final iconWidget = iconColor != null
        ? ColorFiltered(
            colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
            child: icon,
          )
        : icon;
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(28.0),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(28.0),
              child: Container(
                width: 56.0,
                height: 56.0,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 1.0),
                ),
                alignment: Alignment.center,
                child: iconWidget,
              ),
            ),
          ),
          const SizedBox(height: 8.0),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(
              fontSize: 11.0,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
