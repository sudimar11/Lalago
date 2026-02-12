import 'package:flutter/material.dart';
import 'package:foodie_driver/common/common_elevated_button.dart';
import 'package:foodie_driver/common/common_text_field.dart';
import 'package:foodie_driver/ui/phoneAuth/PhoneNumberInputScreen.dart';
import 'package:foodie_driver/utils/extensions/context_extension.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/model/User.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/ui/container/ContainerScreen.dart';
import 'package:foodie_driver/ui/resetPasswordScreen/ResetPasswordScreen.dart';

class LoginScreen extends StatefulWidget {
  @override
  State createState() {
    return _LoginScreen();
  }
}

class _LoginScreen extends State<LoginScreen> {
  TextEditingController _emailController = TextEditingController();
  TextEditingController _passwordController = TextEditingController();
  AutovalidateMode _validate = AutovalidateMode.disabled;
  GlobalKey<FormState> _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: context.dismissKeyboard,
      child: Scaffold(
        appBar: null,
        body: Form(
          key: _key,
          autovalidateMode: _validate,
          child: ListView(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            children: <Widget>[
              const SizedBox(height: 16.0),
              Text(
                'Welcome back,',
                style: TextStyle(
                    color: Colors.black,
                    fontSize: 24.0,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4.0),
              Text(
                'Glad to meet you again!, please login to use the app.',
                style: TextStyle(
                    color: Colors.black54,
                    fontSize: 14.0,
                    fontWeight: FontWeight.w400),
              ),
              const SizedBox(height: 24.0),
              CommonTextField(
                validator: validateEmail,
                controller: _emailController,
                hintText: "Enter email",
                helperText: "Email",
                helperTextStyle: TextStyle(
                    color: Colors.black,
                    fontSize: 14.0,
                    fontWeight: FontWeight.w500),
                hintTextStyle: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14.0,
                    fontWeight: FontWeight.w400),
                inputBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24.0),
                    borderSide: BorderSide(color: Colors.grey, width: 0.5)),
              ),
              const SizedBox(height: 24.0),
              CommonTextField(
                validator: validatePassword,
                controller: _passwordController,
                onFieldSubmitted: (password) => _login(),
                hasShowHideTextIcon: true,
                maxLines: 1,
                hintText: "Enter password",
                helperText: "Password",
                helperTextStyle: TextStyle(
                    color: Colors.black,
                    fontSize: 14.0,
                    fontWeight: FontWeight.w500),
                hintTextStyle: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14.0,
                    fontWeight: FontWeight.w400),
                inputBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24.0),
                    borderSide: BorderSide(color: Colors.grey, width: 0.5)),
              ),
              Align(
                  alignment: Alignment.centerRight,
                  child: CommonElevatedButton(
                    onButtonPressed: () => push(context, ResetPasswordScreen()),
                    backgroundColor: Colors.transparent,
                    text: "Forgot Password?",
                    fontSize: 12.0,
                    fontWeight: FontWeight.w600,
                    fontColor: Color(COLOR_PRIMARY),
                  )),
              const SizedBox(height: 16.0),
              SizedBox(
                height: 50.0,
                width: context.screenWidth,
                child: CommonElevatedButton(
                  onButtonPressed: _login,
                  backgroundColor: Color(COLOR_PRIMARY),
                  borderRadius: BorderRadius.circular(24.0),
                  text: "Log In",
                  fontSize: 16.0,
                  fontWeight: FontWeight.w600,
                  fontColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16.0),
              Row(
                children: [
                  Expanded(
                    child: Divider(
                      color: Colors.grey.shade300,
                      thickness: 0.5,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text("Or"),
                  ),
                  Expanded(
                    child: Divider(
                      color: Colors.grey.shade300,
                      thickness: 0.5,
                    ),
                  )
                ],
              ),
              const SizedBox(height: 16.0),
              SizedBox(
                height: 50.0,
                width: context.screenWidth,
                child: CommonElevatedButton(
                  onButtonPressed: loginWithGoogle,
                  backgroundColor: Colors.white,
                  borderRadius: BorderRadius.circular(24.0),
                  borderSide: BorderSide(color: Color(COLOR_PRIMARY)),
                  custom: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.g_mobiledata,
                        size: 24.0,
                        color: Color(COLOR_PRIMARY),
                      ),
                      const SizedBox(width: 8.0),
                      Text(
                        "Login with Google",
                        style: TextStyle(
                            color: Color(COLOR_PRIMARY),
                            fontSize: 16.0,
                            fontWeight: FontWeight.w600),
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16.0),
              SizedBox(
                height: 50.0,
                width: context.screenWidth,
                child: CommonElevatedButton(
                  onButtonPressed: () =>
                      push(context, PhoneNumberInputScreen(login: true)),
                  backgroundColor: Color(COLOR_PRIMARY),
                  borderRadius: BorderRadius.circular(24.0),
                  custom: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.phone,
                        size: 18.0,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8.0),
                      Text(
                        "Login with Phone Number",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16.0,
                            fontWeight: FontWeight.w600),
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40.0),
            ],
          ),
        ),
      ),
    );
  }

  _login() async {
    if (_key.currentState?.validate() ?? false) {
      _key.currentState!.save();

      await _loginWithEmailAndPassword(
          _emailController.text.trim(), _passwordController.text.trim());
    } else {
      setState(() {
        _validate = AutovalidateMode.onUserInteraction;
      });
    }
  }

  _loginWithEmailAndPassword(String email, String password) async {
    await showProgress(context, "Logging in, please wait...", false);

    dynamic result = await FireStoreUtils.loginWithEmailAndPassword(
        email.trim(), password.trim());

    await hideProgress();

    // Debug logging to identify the issue
    print('🔍 LOGIN DEBUG - Result type: ${result.runtimeType}');
    if (result == null) {
      print('❌ LOGIN DEBUG - Result is NULL');
    } else if (result is String) {
      print('🔍 LOGIN DEBUG - Error message: $result');
    } else if (result is User) {
      print('🔍 LOGIN DEBUG - User found:');
      print('   - Email: ${result.email}');
      print('   - Role: "${result.role}"');
      print('   - Expected: "$USER_ROLE_DRIVER"');
      print('   - Role match: ${result.role == USER_ROLE_DRIVER}');
      print('   - Active: ${result.active}');
      print('   - IsActive: ${result.isActive}');
      print('   - IsReallyActive: ${result.isReallyActive}');
    } else {
      print('❌ LOGIN DEBUG - Unexpected type: ${result.runtimeType}');
      print('   - Value: $result');
    }

    // Check if result is a String (error message)
    if (result != null && result is String) {
      showAlertDialog(context, "Couldn't Authenticate", result, true);
      return;
    }

    // Check if result is a User
    if (result != null && result is User) {
      // Check if user has correct role (trim whitespace and compare)
      String userRole = result.role.trim();
      if (userRole != USER_ROLE_DRIVER) {
        print(
            '❌ LOGIN DEBUG - Role mismatch. User role: "${result.role}" (trimmed: "$userRole"), Expected: "$USER_ROLE_DRIVER"');
        showAlertDialog(
            context,
            "Access Denied",
            "This account is not authorized for driver access. Please use the customer app.",
            true);
        return;
      }

      // Try to update FCM token, but don't fail if it errors
      try {
        final fcmToken = await FireStoreUtils.firebaseMessaging.getToken();
        if (fcmToken != null && fcmToken.isNotEmpty) {
          result.fcmToken = fcmToken;
        }
      } catch (fcmError) {
        print(
            'LOGIN DEBUG: Failed to update FCM token in LoginScreen: $fcmError');
        // Keep existing token, don't fail login
      }

      try {
        await FireStoreUtils.updateCurrentUser(result);
        MyAppState.currentUser = result;

        if (MyAppState.currentUser!.isReallyActive) {
          print(
              '✅ LOGIN DEBUG - Login successful, navigating to ContainerScreen');
          pushAndRemoveUntil(context, ContainerScreen(), false);
        } else {
          print(
              '❌ LOGIN DEBUG - Account not active. Active: ${result.active}, IsActive: ${result.isActive}, IsReallyActive: ${result.isReallyActive}');
          showAlertDialog(
              context,
              "Your account has been disabled, Please contact to admin.",
              "",
              true);
        }
      } catch (error) {
        print('❌ LOGIN DEBUG - Error updating user: $error');
        // Still set the user and proceed if update fails
        MyAppState.currentUser = result;
        if (MyAppState.currentUser!.isReallyActive) {
          pushAndRemoveUntil(context, ContainerScreen(), false);
        } else {
          showAlertDialog(
              context,
              "Your account has been disabled, Please contact to admin.",
              "",
              true);
        }
      }
    } else {
      // If result is null or unexpected type
      print(
          '❌ LOGIN DEBUG - Final else block. Result: $result (type: ${result.runtimeType})');
      showAlertDialog(context, "Couldn't Authenticate",
          'Login failed, Please try again.', true);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  loginWithGoogle() async {
    try {
      await showProgress(context, "Logging in, please wait...", false);

      dynamic result = await FireStoreUtils.loginWithGoogle();

      await hideProgress();

      if (result != null && result is User) {
        MyAppState.currentUser = result;

        if (MyAppState.currentUser!.active == true) {
          pushAndRemoveUntil(context, ContainerScreen(), false);
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
            context, 'error', "Couldn't login with google.", true);
      }
    } catch (e, s) {
      await hideProgress();
      print('_LoginScreen.loginWithGoogle $e $s');
      showAlertDialog(
          context, 'error', "Couldn't login with google.", true);
    }
  }
}
