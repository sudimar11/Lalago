import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:flutter/material.dart';

import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/model/OrderModel.dart';
import 'package:foodie_restaurant/model/OrderProductModel.dart';
import 'package:foodie_restaurant/model/TaxModel.dart';
import 'package:foodie_restaurant/model/variant_info.dart';
import 'package:foodie_restaurant/services/FirebaseHelper.dart';
import 'package:foodie_restaurant/services/helper.dart';
import 'package:foodie_restaurant/ui/ordersScreen/print.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class OrderDetailsScreen extends StatefulWidget {
  final OrderModel orderModel;

  const OrderDetailsScreen({Key? key, required this.orderModel})
      : super(key: key);

  @override
  _OrderDetailsScreenState createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  FireStoreUtils fireStoreUtils = FireStoreUtils();

  double total = 0.0;

  double adminComm = 0.0;

  double specialDiscount = 0.0;

  double discount = 0.0;

  var tipAmount = "0.0";

  @override
  @override
  void initState() {
    super.initState();

    // 1. Sum up product prices + extras
    total = 0.0;
    for (final element in widget.orderModel.products) {
      if (element.extrasPrice != null &&
          element.extrasPrice!.isNotEmpty &&
          double.tryParse(element.extrasPrice!) != null) {
        total += element.quantity * double.parse(element.extrasPrice!);
      }
      total += element.quantity * double.parse(element.price);
    }

    // 2. Calculate discounts
    discount = double.tryParse(widget.orderModel.discount.toString()) ?? 0.0;
    specialDiscount = 0.0;
    if (widget.orderModel.specialDiscount != null &&
        widget.orderModel.specialDiscount!['special_discount'] != null) {
      specialDiscount = double.tryParse(
        widget.orderModel.specialDiscount!['special_discount'].toString(),
      )!;
    }

    // 3. Total after discounts
    final double totalAmount = total - discount - specialDiscount;

    // 4. Count total items
    final int totalQty = widget.orderModel.products
        .fold<int>(0, (sum, item) => sum + item.quantity);

    // 5. Compute admin commission
    if (widget.orderModel.adminCommissionType == 'Percent') {
      adminComm =
          (totalAmount * double.parse(widget.orderModel.adminCommission!)) /
              100;
    } else {
      // fixed fee per item
      adminComm = double.parse(widget.orderModel.adminCommission!) * totalQty;
    }

    // 6. Deduct commission
    total = totalAmount - adminComm;
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? const Color(DARK_CARD_BG_COLOR) : Colors.white,
      appBar: AppBar(
          title: Text(
        "Order Summary",
        style: TextStyle(
            fontFamily: 'Poppinsr',
            letterSpacing: 0.5,
            fontWeight: FontWeight.bold,
            color: isDarkMode(context)
                ? Colors.grey.shade200
                : const Color(0xff333333)),
      )),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildOrderSummaryCard(widget.orderModel),
            Card(
              color: isDarkMode(context)
                  ? const Color(DARK_CARD_BG_COLOR)
                  : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Admin commission",
                          ),
                        ),
                        Text(
                          "(-${amountShow(amount: adminComm.toString())})",
                          style: TextStyle(
                              fontWeight: FontWeight.w600, color: Colors.red),
                        ),
                      ],
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    Text(
                      "Note: Admin commission is already deducted from your total orders. \nAdmin commission will apply on order Amount minus Discount & Special Discount (if applicable).",
                      style: TextStyle(color: Colors.red),
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildOrderSummaryCard(OrderModel orderModel) {
    print("order status ${widget.orderModel.id}");

    // Default specialDiscount to empty map when null
    final Map<String, dynamic> specialDiscount =
        widget.orderModel.specialDiscount ?? {};

    // Default taxModel to empty list when null
    final List<TaxModel> taxModel = widget.orderModel.taxModel ?? [];

    double specialDiscountAmount = 0.0;

    String taxAmount = "0.0";

    // Compute specialDiscountAmount only if the map contains a special_discount key
    if (specialDiscount.isNotEmpty &&
        specialDiscount.containsKey('special_discount')) {
      specialDiscountAmount =
          double.tryParse(specialDiscount['special_discount'].toString()) ??
              0.0;
    }

    // Iterate over the safe taxes list instead of force-unwrapping
    for (var element in taxModel) {
      taxAmount = (double.parse(taxAmount) +
              calculateTax(
                  amount: (total - discount - specialDiscountAmount).toString(),
                  taxModel: element))
          .toString();
    }

    var totalamount =
        total + double.parse(taxAmount) - discount - specialDiscountAmount;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Card(
        color: isDarkMode(context)
            ? const Color(DARK_CARD_BG_COLOR)
            : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 14, right: 14, top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                height: 15,
              ),
              ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: widget.orderModel.products.length,
                  itemBuilder: (context, index) {
                    VariantInfo? variantIno =
                        widget.orderModel.products[index].variantInfo;

                    List<dynamic>? addon =
                        widget.orderModel.products[index].extras;

                    String extrasDisVal = '';

                    for (int i = 0; i < addon!.length; i++) {
                      extrasDisVal +=
                          '${addon[i].toString().replaceAll("\"", "")} ${(i == addon.length - 1) ? "" : ","}';
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CachedNetworkImage(
                                height: 55,
                                width: 55,

                                // width: 50,

                                imageUrl:
                                    widget.orderModel.products[index].photo,
                                imageBuilder: (context, imageProvider) =>
                                    Container(
                                      decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          image: DecorationImage(
                                            image: imageProvider,
                                            fit: BoxFit.cover,
                                          )),
                                    ),
                                errorWidget: (context, url, error) => ClipRRect(
                                    borderRadius: BorderRadius.circular(15),
                                    child: Image.network(
                                      placeholderImage,
                                      fit: BoxFit.cover,
                                      width: MediaQuery.of(context).size.width,
                                      height:
                                          MediaQuery.of(context).size.height,
                                    ))),
                            Padding(
                              padding: const EdgeInsets.only(left: 10.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        widget.orderModel.products[index].name,
                                        style: TextStyle(
                                            fontFamily: 'Poppinsr',
                                            fontSize: 14,
                                            letterSpacing: 0.5,
                                            fontWeight: FontWeight.bold,
                                            color: isDarkMode(context)
                                                ? Colors.grey.shade200
                                                : const Color(0xff333333)),
                                      ),
                                      Text(
                                        ' x ${widget.orderModel.products[index].quantity}',
                                        style: TextStyle(
                                            fontFamily: 'Poppinsr',
                                            letterSpacing: 0.5,
                                            color: isDarkMode(context)
                                                ? Colors.grey.shade200
                                                : Colors.black
                                                    .withValues(alpha: 0.60)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  getPriceTotalText(
                                      widget.orderModel.products[index]),
                                ],
                              ),
                            )
                          ],
                        ),
                        const SizedBox(
                          height: 10,
                        ),
                        variantIno == null || variantIno.variantOptions!.isEmpty
                            ? Container()
                            : Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 5),
                                child: Wrap(
                                  spacing: 6.0,
                                  runSpacing: 6.0,
                                  children: List.generate(
                                    variantIno.variantOptions!.length,
                                    (i) {
                                      return _buildChip(
                                          "${variantIno.variantOptions!.keys.elementAt(i)} : ${variantIno.variantOptions![variantIno.variantOptions!.keys.elementAt(i)]}",
                                          i);
                                    },
                                  ).toList(),
                                ),
                              ),
                        const SizedBox(
                          height: 5,
                        ),
                        Container(
                          margin: const EdgeInsets.only(left: 5, right: 10),
                          child: extrasDisVal.isEmpty
                              ? Container()
                              : Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    extrasDisVal,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey,
                                        fontFamily: 'Poppinsr'),
                                  ),
                                ),
                        ),
                      ],
                    );
                  }),
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                title: Text(
                  'Subtotal'.tr(),
                  style: TextStyle(
                    fontFamily: 'Poppinsm',
                    fontSize: 16,
                    letterSpacing: 0.5,
                    color: isDarkMode(context)
                        ? Colors.grey.shade300
                        : const Color(0xff9091A4),
                  ),
                ),
                trailing: Text(
                  amountShow(amount: total.toString()),
                  style: TextStyle(
                    fontFamily: 'Poppinssm',
                    letterSpacing: 0.5,
                    fontSize: 16,
                    color: isDarkMode(context)
                        ? Colors.grey.shade300
                        : const Color(0xff333333),
                  ),
                ),
              ),
              Visibility(
                visible: orderModel.vendor.specialDiscountEnable &&
                    specialDiscount.isNotEmpty,
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                  title: Text(
                    'Special Discount'.tr() +
                        "(${specialDiscount['special_discount_label'] ?? ''}${specialDiscount['specialType'] == "amount" ? currencyModel!.symbol : "%"})",
                    style: TextStyle(
                      fontFamily: 'Poppinsm',
                      fontSize: 16,
                      letterSpacing: 0.5,
                      color: isDarkMode(context)
                          ? Colors.grey.shade300
                          : const Color(0xff9091A4),
                    ),
                  ),
                  trailing: Text(
                    "(-${amountShow(amount: specialDiscountAmount.toString())})",
                    style: TextStyle(
                        fontFamily: 'Poppinssm',
                        letterSpacing: 0.5,
                        fontSize: 16,
                        color: Colors.red),
                  ),
                ),
              ),
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                title: Text(
                  'Discount'.tr(),
                  style: TextStyle(
                    fontFamily: 'Poppinsm',
                    fontSize: 16,
                    letterSpacing: 0.5,
                    color: isDarkMode(context)
                        ? Colors.grey.shade300
                        : const Color(0xff9091A4),
                  ),
                ),
                trailing: Text(
                  "(-${amountShow(amount: discount.toString())})",
                  style: TextStyle(
                      fontFamily: 'Poppinssm',
                      letterSpacing: 0.5,
                      fontSize: 16,
                      color: Colors.red),
                ),
              ),
              ListView.builder(
                itemCount: taxModel.length,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  TaxModel currentTaxModel = taxModel[index];

                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                    title: Text(
                      '${currentTaxModel.title.toString()} (${currentTaxModel.type == "fix" ? amountShow(amount: currentTaxModel.tax) : "${currentTaxModel.tax}%"})',
                      style: TextStyle(
                        fontFamily: 'Poppinsm',
                        fontSize: 16,
                        letterSpacing: 0.5,
                        color: isDarkMode(context)
                            ? Colors.grey.shade300
                            : const Color(0xff9091A4),
                      ),
                    ),
                    trailing: Text(
                      amountShow(
                          amount: calculateTax(
                                  amount: (double.parse(total.toString()) -
                                          discount -
                                          specialDiscountAmount)
                                      .toString(),
                                  taxModel: currentTaxModel)
                              .toString()),
                      style: TextStyle(
                        fontFamily: 'Poppinssm',
                        letterSpacing: 0.5,
                        fontSize: 16,
                        color: isDarkMode(context)
                            ? Colors.grey.shade300
                            : const Color(0xff333333),
                      ),
                    ),
                  );
                },
              ),
              (widget.orderModel.notes != null &&
                      widget.orderModel.notes!.isNotEmpty)
                  ? ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0, vertical: 0),
                      title: Text(
                        "Remarks".tr(),
                        style: TextStyle(
                          fontFamily: 'Poppinsm',
                          fontSize: 17,
                          letterSpacing: 0.5,
                          color: isDarkMode(context)
                              ? Colors.grey.shade300
                              : const Color(0xff9091A4),
                        ),
                      ),
                      trailing: InkWell(
                        onTap: () {
                          showModalBottomSheet(
                              isScrollControlled: true,
                              isDismissible: true,
                              context: context,
                              backgroundColor: Colors.transparent,
                              enableDrag: true,
                              builder: (BuildContext context) =>
                                  viewNotesheet(widget.orderModel.notes!));
                        },
                        child: Text(
                          "View".tr(),
                          style: TextStyle(
                              fontSize: 18,
                              color: Color(COLOR_PRIMARY),
                              letterSpacing: 0.5,
                              fontFamily: 'Poppinsm'),
                        ),
                      ),
                    )
                  : Container(),
              widget.orderModel.couponCode!.trim().isNotEmpty
                  ? ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0, vertical: 0),
                      title: Text(
                        'Coupon Code'.tr(),
                        style: TextStyle(
                          fontFamily: 'Poppinsm',
                          fontSize: 16,
                          letterSpacing: 0.5,
                          color: isDarkMode(context)
                              ? Colors.grey.shade300
                              : const Color(0xff9091A4),
                        ),
                      ),
                      trailing: Text(
                        widget.orderModel.couponCode!,
                        style: TextStyle(
                          fontFamily: 'Poppinsm',
                          letterSpacing: 0.5,
                          fontSize: 16,
                          color: isDarkMode(context)
                              ? Colors.grey.shade300
                              : const Color(0xff333333),
                        ),
                      ),
                    )
                  : Container(),
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                title: Text(
                  'Order Total'.tr(),
                  style: TextStyle(
                    fontFamily: 'Poppinsm',
                    letterSpacing: 0.5,
                  ),
                ),
                trailing: Text(
                  amountShow(amount: totalamount.toString()),
                  style: TextStyle(
                    fontFamily: 'Poppinssm',
                    letterSpacing: 0.5,
                    fontSize: 22,
                    color: Color(COLOR_PRIMARY),
                  ),
                ),
              ),
              //ElevatedButton(
              //  onPressed: () {
              //    Navigator.push(
              //      context,
              //      MaterialPageRoute(
              //          builder: (context) => BluetoothPrinterPage()),
              //    );
              //  },
              //  child: const Text("Go to Bluetooth Printer"),
              //),
              Visibility(
                visible: orderModel.status != ORDER_STATUS_DRIVER_REJECTED,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: InkWell(
                    child: Container(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        decoration: BoxDecoration(
                            color: Color(COLOR_PRIMARY),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                                width: 0.8, color: Color(COLOR_PRIMARY))),
                        child: Center(
                          child: Text(
                            'Print Invoice'.tr(),
                            style: TextStyle(
                                color: isDarkMode(context)
                                    ? const Color(0xffFFFFFF)
                                    : Colors.white,
                                fontFamily: "Poppinsm",
                                fontSize: 15

                                // fontWeight: FontWeight.bold,

                                ),
                          ),
                        )),
                    onTap: () {
                      printTicket();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> printTicket() async {
    String? isConnected =
        await PrintBluetoothThermal.connectionStatus.toString();

    if (isConnected == "true") {
      List<int> bytes = await getTicket();
      final String? result =
          await PrintBluetoothThermal.writeBytes(bytes).toString();

      if (result == "true") {
        showAlertDialog(
            context, "Success", "Invoice printed successfully.", true);
      } else {
        showAlertDialog(
            context, "Error", "Failed to print the invoice.", false);
      }
    } else {
      showAlertDialog(context, "Not Connected",
          "Please connect to a printer first.", false);
      getBluetooth();
    }
  }

  String taxAmount = "0.0";
  Future<List<int>> getTicket() async {
    List<int> bytes = [];
    CapabilityProfile profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);

    bytes += generator.text("Invoice",
        styles: const PosStyles(align: PosAlign.center, bold: true),
        linesAfter: 1);

    bytes += generator.text(widget.orderModel.vendor.title,
        styles: const PosStyles(align: PosAlign.center));

    bytes += generator.text('Tel: ${widget.orderModel.vendor.phonenumber}',
        styles: const PosStyles(align: PosAlign.center));

    bytes += generator.hr();

    for (var product in widget.orderModel.products) {
      bytes += generator.text(
        "Item: ${product.name} x ${product.quantity}",
        styles: const PosStyles(align: PosAlign.left),
      );
      bytes += generator.text("Price: ${product.price}",
          styles: const PosStyles(align: PosAlign.left));
    }

    bytes += generator.hr();

    bytes += generator.text("Thank you!",
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.cut();

    return bytes;
  }

  List availableBluetoothDevices = [];

  Future<void> getBluetooth() async {
    try {
      final List? bluetooths = await PrintBluetoothThermal.pairedBluetooths;

      if (bluetooths == null || bluetooths.isEmpty) {
        showAlertDialog(
          context,
          "No Devices Found",
          "No paired Bluetooth devices were found. Please pair your printer in the Bluetooth settings.",
          false,
        );
        return;
      }

      print("Paired devices: $bluetooths");

      setState(() {
        availableBluetoothDevices = bluetooths;
      });

      showLoadingAlert();
    } catch (e) {
      print("Error fetching Bluetooth devices: $e");

      showAlertDialog(
        context,
        "Error",
        "Failed to retrieve Bluetooth devices. Please try again.",
        false,
      );
    }
  }

  void showLoadingAlert() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Connect Bluetooth Device').tr(),
          content: SizedBox(
            width: double.maxFinite,
            child: availableBluetoothDevices.isEmpty
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      const Text("Searching for devices...").tr(),
                      const SizedBox(height: 8),
                      const Text(
                        "If no devices are found, please pair your printer in Bluetooth settings.",
                        textAlign: TextAlign.center,
                      ).tr(),
                    ],
                  )
                : ListView.builder(
                    itemCount: availableBluetoothDevices.length,
                    shrinkWrap: true,
                    itemBuilder: (context, index) {
                      String select = availableBluetoothDevices[index];
                      List<String> deviceInfo = select.split("#");
                      String deviceName = deviceInfo[0];
                      String mac = deviceInfo[1];

                      return ListTile(
                        onTap: () {
                          setConnect(mac);
                          Navigator.pop(context);
                        },
                        title: Text(deviceName.isNotEmpty
                            ? deviceName
                            : "Unknown Device"),
                        subtitle: Text("MAC: $mac").tr(),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel").tr(),
            ),
          ],
        );
      },
    );
  }

  Future<void> setConnect(String mac) async {
    try {
      final bool result =
          await PrintBluetoothThermal.connect(macPrinterAddress: mac);

      if (result == "true") {
        print("Connected to device: $mac");
        showAlertDialog(context, "Success", "Connected to the printer.", true);
      } else {
        showAlertDialog(
            context, "Failed", "Could not connect to the printer.", false);
      }
    } catch (e) {
      print("Error connecting to printer: $e");
      showAlertDialog(
          context, "Error", "An error occurred while connecting.", false);
    }
  }

  getPriceTotalText(OrderProductModel s) {
    double total = 0.0;

    if (s.extrasPrice != null &&
        s.extrasPrice!.isNotEmpty &&
        double.parse(s.extrasPrice!) != 0.0) {
      total += s.quantity * double.parse(s.extrasPrice!);
    }

    total += s.quantity * double.parse(s.price);

    return Text(
      amountShow(amount: total.toString()),
      style: TextStyle(
        fontSize: 15,
      ),
    );
  }

  viewNotesheet(String notes) {
    return Container(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height / 4.3,
          left: 25,
          right: 25),
      height: MediaQuery.of(context).size.height * 0.80,
      decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border.all(style: BorderStyle.none)),
      child: Column(
        children: [
          InkWell(
              onTap: () => Navigator.pop(context),
              child: Container(
                height: 45,

                decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 0.3),
                    color: Colors.transparent,
                    shape: BoxShape.circle),

                // radius: 20,

                child: const Center(
                  child: Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              )),
          const SizedBox(
            height: 25,
          ),
          Expanded(
              child: Container(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: isDarkMode(context)
                    ? const Color(0XFF2A2A2A)
                    : Colors.white),
            alignment: Alignment.center,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                      padding: const EdgeInsets.only(top: 20),
                      child: Text(
                        'Remark'.tr(),
                        style: TextStyle(
                            fontFamily: 'Poppinssb',
                            color: isDarkMode(context)
                                ? Colors.white70
                                : Colors.black,
                            fontSize: 16),
                      )),
                  Container(
                    padding:
                        const EdgeInsets.only(left: 20, right: 20, top: 20),

                    // height: 120,

                    child: ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(12)),
                      child: Container(
                        padding: const EdgeInsets.only(
                            left: 20, right: 20, top: 20, bottom: 20),

                        color: isDarkMode(context)
                            ? const Color(DARK_CARD_BG_COLOR)
                            : const Color(0XFFF1F4F7),

                        // height: 120,

                        alignment: Alignment.center,

                        child: Text(
                          notes,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isDarkMode(context)
                                ? Colors.white70
                                : Colors.black,
                            fontFamily: 'Poppinsm',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )),
        ],
      ),
    );
  }
}

Widget _buildChip(String label, int attributesOptionIndex) {
  return Container(
    decoration: BoxDecoration(
        color: const Color(0xffEEEDED), borderRadius: BorderRadius.circular(4)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.black,
        ),
      ),
    ),
  );
}
