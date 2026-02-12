import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:foodie_customer/common/common_elevated_button.dart';
import 'package:foodie_customer/common/common_text_field.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/services/helper.dart';

const List<String> _feedbackCategories = [
  'App Experience',
  'Ordering',
  'Delivery',
  'Rider Attitude',
  'Restaurant',
  'Suggestion',
  'Other',
];

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  int _rating = 1;
  String _category = _feedbackCategories.first;
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final result = await Connectivity().checkConnectivity();
    final isOffline = result == ConnectivityResult.none;
    if (isOffline) {
      setState(() {
        _errorMessage =
            'No Internet. Please check your connection and try again.';
        _isSubmitting = false;
      });
      return;
    }

    if (auth.FirebaseAuth.instance.currentUser == null ||
        MyAppState.currentUser == null) {
      setState(() {
        _errorMessage = 'Please sign in again.';
        _isSubmitting = false;
      });
      return;
    }

    try {
      final user = MyAppState.currentUser!;
      final map = <String, dynamic>{
        'user_id': auth.FirebaseAuth.instance.currentUser!.uid,
        'user_name': user.fullName(),
        'rating': _rating,
        'category': _category,
        'comment': _commentController.text.trim(),
        'created_at': FieldValue.serverTimestamp(),
        'is_deleted': false,
      };
      await FirebaseFirestore.instance
          .collection(CUSTOMER_FEEDBACK)
          .add(map);

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = null;
      });
      _commentController.clear();
      setState(() {
        _rating = 1;
        _category = _feedbackCategories.first;
      });
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Thank you'),
          content: const Text(
            'Thank you for your feedback. We appreciate you taking the '
            'time to help us improve.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e, stackTrace) {
      debugPrint('Feedback submit error: $e');
      debugPrint('Feedback submit stackTrace: $stackTrace');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to submit. Please try again.';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    final bgColor = dark ? const Color(DARK_COLOR) : null;
    final cardColor = dark ? const Color(0xff35363A) : const Color(0XFFFDFEFE);
    final textColor = dark ? Colors.white : Colors.black;

    return SafeArea(
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: Color(COLOR_PRIMARY),
          elevation: 0,
          iconTheme: IconThemeData(
            color: dark ? Colors.grey.shade200 : Colors.white,
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          title: const SizedBox.shrink(),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Rate your experience',
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              RatingBar.builder(
                initialRating: _rating.toDouble(),
                minRating: 1,
                maxRating: 5,
                allowHalfRating: false,
                itemCount: 5,
                itemPadding: const EdgeInsets.symmetric(horizontal: 6),
                itemBuilder: (context, _) => Icon(
                  Icons.star,
                  color: Color(COLOR_PRIMARY),
                ),
                onRatingUpdate: (double rate) {
                  setState(() => _rating = rate.round());
                },
              ),
              const SizedBox(height: 24),
              Text(
                'Category',
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: dark ? Colors.grey.shade700 : Colors.grey.shade300,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _category,
                    isExpanded: true,
                    dropdownColor: cardColor,
                    style: TextStyle(color: textColor, fontSize: 16),
                    items: _feedbackCategories
                        .map((String value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            ))
                        .toList(),
                    onChanged: (String? value) {
                      if (value != null) {
                        setState(() => _category = value);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Your feedback',
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              CommonTextField(
                controller: _commentController,
                hintText: 'Your feedback or suggestion...',
                maxLines: 5,
                minLines: 4,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                SelectableText(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 14),
                ),
              ],
              const SizedBox(height: 24),
              CommonElevatedButton(
                text: 'Submit',
                isLoading: _isSubmitting,
                onButtonPressed: _onSubmit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
