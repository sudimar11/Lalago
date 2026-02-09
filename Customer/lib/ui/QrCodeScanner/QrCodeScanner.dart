import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/vendorProductsScreen/newVendorProductsScreen.dart';

class QrCodeScanner extends StatefulWidget {
  const QrCodeScanner({Key? key}) : super(key: key);

  @override
  State<QrCodeScanner> createState() => _QrCodeScannerState();
}

class _QrCodeScannerState extends State<QrCodeScanner> {
  final TextEditingController _codeController = TextEditingController();
  final List<VendorModel> allstoreList = [];
  bool _isProcessing = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _processCode(String code) {
    if (code.isEmpty) {
      _showError("Please enter a code");
      return;
    }

    print("Entered code: $code");
    setState(() {
      _isProcessing = true;
    });

    try {
      Map<String, dynamic> codeVal = jsonDecode(code);
      print("codeVal: $codeVal  ${allstoreList.isNotEmpty}");

      if (allstoreList.isNotEmpty) {
        for (VendorModel storeModel in allstoreList) {
          print("store name ${storeModel.id}");
          if (storeModel.id == codeVal["vendorid"]) {
            Navigator.of(context).pop();
            push(context, NewVendorProductsScreen(vendorModel: storeModel));
            return;
          }
        }
      }

      _showError("Store not available");
    } catch (e) {
      print("Error decoding code: $e");
      _showError("Invalid QR Code");
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _showError(String message) {
    showAlertDialog(context, "error", message, true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          title: Text(
            "QR Code Scanner",
            style: TextStyle(
              fontFamily: "Poppinsr",
              letterSpacing: 0.5,
              fontWeight: FontWeight.normal,
              color: isDarkMode(context) ? Colors.white : Colors.black,
            ),
          ),
          centerTitle: false,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: Icon(
              Icons.chevron_left,
              color: isDarkMode(context) ? Colors.white : Colors.black,
              size: 40,
            ),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ),
        body: Container(
          margin: const EdgeInsets.only(left: 10, right: 10),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.qr_code_scanner,
                    size: 80,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Scan temporarily unavailable",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode(context) ? Colors.white : Colors.black,
                      fontFamily: "Poppinssb",
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      "Please enter code manually",
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        fontFamily: "Poppinsr",
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      controller: _codeController,
                      decoration: InputDecoration(
                        labelText: "Enter QR/Bar code",
                        hintText: "Paste or type the code here",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: const Icon(Icons.qr_code),
                      ),
                      maxLines: 3,
                      textCapitalization: TextCapitalization.none,
                    ),
                  ),
                  const SizedBox(height: 30),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isProcessing
                            ? null
                            : () {
                                _processCode(_codeController.text.trim());
                              },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _isProcessing
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                "Validate Code",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontFamily: "Poppinssb",
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
