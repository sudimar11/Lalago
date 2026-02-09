import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:foodie_customer/common/common_elevated_button.dart';
import 'package:foodie_customer/common/common_image.dart';
import 'package:foodie_customer/common/common_text_field.dart';

import 'package:foodie_customer/ui/location_permission_screen.dart';
import 'package:foodie_customer/utils/extensions/context_extension.dart';

import 'package:foodie_customer/constants.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:foodie_customer/main.dart';

import 'package:foodie_customer/model/User.dart';

import 'package:foodie_customer/services/FirebaseHelper.dart';

import 'package:foodie_customer/services/helper.dart';

import 'package:foodie_customer/ui/container/ContainerScreen.dart';

import 'package:foodie_customer/ui/phoneAuth/PhoneNumberInputScreen.dart';

import 'package:foodie_customer/ui/resetPasswordScreen/ResetPasswordScreen.dart';

import '../../resources/assets.dart';
import '../../resources/colors.dart';
import '../vendorProductsScreen/widgets/ficon_button.dart';

class LoginScreen extends StatefulWidget {
  @override
  State createState() {
    return _LoginScreen();
  }
}

class _LoginScreen extends State<LoginScreen> {
  bool _obscureText = true; // To control password visibility

  void _togglePasswordVisibility() {
    setState(() {
      _obscureText = !_obscureText;
    });
  }

  TextEditingController _emailController = TextEditingController();

  TextEditingController _passwordController = TextEditingController();

  AutovalidateMode _validate = AutovalidateMode.disabled;

  GlobalKey<FormState> _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: context.dismissKeyboard,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
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
                    fontColor: CustomColors.primary,
                  )),
              const SizedBox(height: 16.0),
              SizedBox(
                height: 50.0,
                width: context.screenWidth,
                child: CommonElevatedButton(
                  onButtonPressed: _login,
                  borderRadius: BorderRadius.circular(24.0),
                  text: "Log In",
                  fontSize: 16.0,
                  fontWeight: FontWeight.w600,
                  fontColor: Colors.white,
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
              const SizedBox(height: 16.0),
              SizedBox(
                height: 50.0,
                width: context.screenWidth,
                child: CommonElevatedButton(
                  onButtonPressed: loginWithGoogle,
                  backgroundColor: Colors.white,
                  borderRadius: BorderRadius.circular(24.0),
                  borderSide: BorderSide(color: CustomColors.primary),
                  custom: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 8.0,
                    children: [
                      CommonImage(
                          path: Assets.google, height: 18.0, width: 18.0),
                      Text(
                        "Login with Google",
                        style: TextStyle(
                            color: CustomColors.primary,
                            fontSize: 16.0,
                            fontWeight: FontWeight.w600),
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16.0),
              _buildSignInWithAppleButton(context),
              const SizedBox(height: 16.0),
              SizedBox(
                height: 50.0,
                width: context.screenWidth,
                child: CommonElevatedButton(
                  onButtonPressed: () =>
                      push(context, PhoneNumberInputScreen(login: true)),
                  backgroundColor: CustomColors.primary,
                  borderRadius: BorderRadius.circular(24.0),
                  custom: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 8.0,
                    children: [
                      CommonImage(
                          path: Assets.icPhoneCall, height: 18.0, width: 18.0),
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

  Widget _buildSignInWithAppleButton(BuildContext context) {
    return FutureBuilder<bool>(
      future: SignInWithApple.isAvailable(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        if (snapshot.hasData && snapshot.data == true) {
          return SizedBox(
            height: 50.0,
            width: context.screenWidth,
            child: SignInWithAppleButton(
              onPressed: loginWithApple,
              height: 50.0,
              style: isDarkMode(context)
                  ? SignInWithAppleButtonStyle.white
                  : SignInWithAppleButtonStyle.black,
              borderRadius: BorderRadius.circular(24.0),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  _login() async {
    if (_key.currentState?.validate() ?? false) {
      _key.currentState!.save();

      debugPrint(
        'LOGIN attempt: email=${_emailController.text.trim()}',
      );

      await _loginWithEmailAndPassword(
          _emailController.text.trim(), _passwordController.text.trim());
    } else {
      setState(() {
        _validate = AutovalidateMode.onUserInteraction;
      });
    }
  }

  /// login with email and password with firebase

  /// @param email user email

  /// @param password user password

  _loginWithEmailAndPassword(String email, String password) async {
    try {
      await showProgress(context, "Logging in, please wait...", false);
    } catch (e) {
      debugPrint('LOGIN showProgress failed: $e');
    }

    dynamic result = await FireStoreUtils.loginWithEmailAndPassword(
        email.trim(), password.trim());

    try {
      await hideProgress();
    } catch (e) {
      debugPrint('LOGIN hideProgress failed: $e');
    }

    if (!mounted) return;

    debugPrint(
      'LOGIN result type=${result.runtimeType} '
      'role=${result is User ? result.role : 'null'} '
      'active=${result is User ? result.active : 'null'}',
    );

    if (result != null && result is User && result.role == USER_ROLE_CUSTOMER) {
      await FireStoreUtils.updateCurrentUser(result).then((value) {
        if (!mounted) return;
        MyAppState.currentUser = result;
        unawaited(FireStoreUtils.refreshFcmTokenForUser(result));

        print(MyAppState.currentUser!.active.toString() + "===S");

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
      });
    } else if (result != null && result is String) {
      debugPrint('LOGIN auth error: $result');
      if (!mounted) return;
      showAlertDialog(context, "Couldn't Authenticate", result, true);
    } else {
      if (!mounted) return;
      showAlertDialog(context, "Couldn't Authenticate",
          'The username or password you entered is incorrect.', true);
    }
  }

  ///dispose text editing controllers to avoid memory leaks

  @override
  void dispose() {
    _emailController.dispose();

    _passwordController.dispose();

    super.dispose();
  }

  loginWithFacebook() async {
    try {
      await showProgress(context, "Logging in, please wait...", false);

      dynamic result = await FireStoreUtils.loginWithFacebook();

      await hideProgress();

      if (!mounted) return;

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
            context, 'error', "Couldn't login with facebook.", true);
      }
    } catch (e, s) {
      await hideProgress();

      print('_LoginScreen.loginWithFacebook $e $s');

      if (!mounted) return;
      showAlertDialog(context, 'error', "Couldn't login with facebook.", true);
    }
  }

  loginWithApple() async {
    try {
      await showProgress(context, "Logging in, please wait...", false);

      dynamic result = await FireStoreUtils.loginWithApple();

      await hideProgress();

      if (!mounted) return;

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
        showAlertDialog(context, 'error', "Couldn't login with apple.", true);
      }
    } catch (e, s) {
      await hideProgress();

      print('_LoginScreen.loginWithApple $e $s');

      if (!mounted) return;
      showAlertDialog(context, 'error', "Couldn't login with apple.", true);
    }
  }

  loginWithGoogle() async {
    try {
      // Do NOT show progress before loginWithGoogle on iOS: the progress modal
      // prevents googleSignIn.signIn() from presenting the account picker,
      // causing a hang.
      dynamic result = await FireStoreUtils.loginWithGoogle();

      await hideProgress();

      if (!mounted) return;

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
        showAlertDialog(context, 'error', "Couldn't login with google.", true);
      }
    } catch (e, s) {
      try {
        await hideProgress();
      } catch (_) {}
      print('_LoginScreen.loginWithGoogle $e $s');
      if (!mounted) return;
      showAlertDialog(context, 'error', "Couldn't login with google.", true);
    }
  }
}
