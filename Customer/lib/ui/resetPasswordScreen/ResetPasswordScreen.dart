import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:foodie_customer/common/common_elevated_button.dart';
import 'package:foodie_customer/common/common_text_field.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/utils/extensions/context_extension.dart';

import '../../resources/colors.dart';

class ResetPasswordScreen extends StatefulWidget {
  @override
  _ResetPasswordScreenState createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  GlobalKey<FormState> _key = GlobalKey();
  AutovalidateMode _validate = AutovalidateMode.disabled;

  TextEditingController _emailController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: context.dismissKeyboard,
      child: Scaffold(
        appBar: null,
        body: Form(
          autovalidateMode: _validate,
          key: _key,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16.0),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Reset Password',
                          style: TextStyle(
                              color: CustomColors.primary,
                              fontSize: 24.0,
                              fontWeight: FontWeight.w500))
                      ,
                ),
                const SizedBox(height: 16.0),
                CommonTextField(
                  controller: _emailController,
                  validator: validateEmail,
                  onFieldSubmitted: (_) => resetPassword(),
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
                SizedBox(
                  height: 50.0,
                  width: context.screenWidth,
                  child: CommonElevatedButton(
                    onButtonPressed: resetPassword,
                    borderRadius: BorderRadius.circular(24.0),
                    text: "Send Link",
                    fontSize: 16.0,
                    fontWeight: FontWeight.w600,
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  resetPassword() async {
    if (_key.currentState?.validate() ?? false) {
      _key.currentState!.save();
      showProgress(context, "Sending Email...", false);

      try {
        log("meron ba email? ${_emailController.text}");
        await FireStoreUtils.resetPassword(_emailController.text.trim());
        hideProgress();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please check your email.'),
          ),
        );
      } on auth.FirebaseAuthException catch (e, s) {
        log("Stack: $s");
        hideProgress();
        String message = e.message ?? 'Failed to send reset email';

        switch (e.code) {
          case 'user-not-found':
            message = 'No user found with this email.';
            break;
          case 'invalid-email':
            message = 'Enter valid e-mail';
            break;
          case 'missing-android-pkg-name':
            message = 'App is misconfigured. Please contact support.';
            break;
          default:
            message = 'Something went wrong, try again.';
        }

        log("Reset password error: ${e.code} - $message");

        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      } catch (e) {
        hideProgress();
        log("Unexpected reset password error: ${e.toString()}");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Something went wrong, try again.')),
        );
      }
    } else {
      setState(() {
        _validate = AutovalidateMode.onUserInteraction;
      });
    }
  }
}
