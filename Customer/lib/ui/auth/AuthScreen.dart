import 'package:flutter/material.dart';
import 'package:foodie_customer/common/common_elevated_button.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/login/LoginScreen.dart';
import 'package:foodie_customer/ui/signUp/SignUpScreen.dart';
import 'package:foodie_customer/utils/extensions/context_extension.dart';

import '../../resources/colors.dart';

class AuthScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? Color(DARK_VIEWBG_COLOR) : Colors.white,
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Center(
            child: Image.asset(
              'assets/images/app_logo.png',
              fit: BoxFit.cover,
              width: 150,
              height: 150,
            ),
          ),
          const SizedBox(height: 36.0),
          RichText(
            text: TextSpan(children: [
              TextSpan(
                  text: "Welcome to ",
                  style: TextStyle(
                      color: Colors.black,
                      fontSize: 24.0,
                      fontWeight: FontWeight.w500)),
              TextSpan(
                  text: "LalaGo",
                  style: TextStyle(
                      color: CustomColors.primary,
                      fontSize: 24.0,
                      fontWeight: FontWeight.w600))
            ]),
          ),
          const SizedBox(height: 4.0),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36.0),
            child: Text(
              "Order food from restaurants around you and track food in real-time",
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.black87,
                  fontSize: 14.0,
                  fontWeight: FontWeight.w400),
            ),
          ),
          const SizedBox(height: 24.0),
          Container(
            height: 50.0,
            width: context.screenWidth,
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: CommonElevatedButton(
              onButtonPressed: () => push(context, LoginScreen()),
              borderRadius: BorderRadius.circular(24.0),
              text: "Login",
              fontColor: Colors.white,
              fontSize: 16.0,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16.0),
          Container(
            height: 50.0,
            width: context.screenWidth,
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: CommonElevatedButton(
              onButtonPressed: () => push(context, SignUpScreen()),
              backgroundColor: Colors.white,
              borderRadius: BorderRadius.circular(24.0),
              borderSide: BorderSide(color: CustomColors.primary),
              text: "Register",
              fontColor: CustomColors.primary,
              fontSize: 16.0,
              fontWeight: FontWeight.w600,
            ),
          )
        ],
      ),
    );
  }
}
