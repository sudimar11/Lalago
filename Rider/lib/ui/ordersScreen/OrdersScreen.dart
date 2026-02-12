//import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/model/OrderModel.dart';
import 'package:foodie_driver/model/OrderProductModel.dart';
import 'package:foodie_driver/model/variant_info.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:foodie_driver/services/helper.dart';

class OrdersScreen extends StatefulWidget {
  @override
  _OrdersScreenState createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late Future<List<OrderModel>> ordersFuture;
  FireStoreUtils _fireStoreUtils = FireStoreUtils();
  List<OrderModel> ordersList = [];

  @override
  void initState() {
    super.initState();

    // Add null check
    if (MyAppState.currentUser?.userID == null) {
      ordersFuture = Future.value([]);
      return;
    }

    ordersFuture =
        _fireStoreUtils.getDriverOrders(MyAppState.currentUser!.userID);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {
            ordersFuture =
                _fireStoreUtils.getDriverOrders(MyAppState.currentUser!.userID);
          });
          // wait for the new data to load before ending the spinner
          await ordersFuture;
        },
        // the child must be scrollable — we let the FutureBuilder return a ListView
        child: FutureBuilder<List<OrderModel>>(
          future: ordersFuture,
          initialData: const [],
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.5,
                  ),
                  Center(
                    child: Text(
                      'Failed to load orders. Pull to retry.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  ),
                ],
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator.adaptive(),
              );
            }

            // no orders → still wrap in a ListView so RefreshIndicator works
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.5,
                  ),
                  Center(
                    child: showEmptyState(
                      'No Previous Orders',
                      description: "Let's deliver food!",
                    ),
                  ),
                ],
              );
            }

            // got orders → build the list
            final ordersList = snapshot.data!;
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: ordersList.length,
              itemBuilder: (context, index) =>
                  buildOrderItem(ordersList[index]),
            );
          },
        ),
      ),
    );
  }

  Widget buildOrderItem(OrderModel orderModel) {
    double total = 0.0;
    orderModel.products.forEach((element) {
      total += element.quantity * double.parse(element.price);
    });

    // Precompute display data for all products
    final productDisplayData = orderModel.products.map((product) {
      final addon = product.extras ?? [];
      final extrasDisVal = addon.isEmpty
          ? ''
          : addon.asMap().entries.map((e) =>
                  '${e.value.toString().replaceAll("\"", "")}${e.key == addon.length - 1 ? "" : ","}')
              .join(' ');
      return (product: product, extrasDisplay: extrasDisVal);
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Container(
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: Colors.grey.shade100, width: 0.1),
            boxShadow: [
              BoxShadow(
                  color: Colors.grey.shade200,
                  blurRadius: 2.0,
                  spreadRadius: 0.4,
                  offset: Offset(0.2, 0.2)),
            ],
            color: Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(10)),
              child: Container(
                height: 140,
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: NetworkImage(orderModel.products.first.photo),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                        Colors.black.withValues(alpha: 0.5), BlendMode.darken),
                  ),
                ),
                child: Center(
                  child: Text(
                    '${orderDate(orderModel.createdAt)} - ${orderModel.status}',
                    style: TextStyle(color: Colors.white, fontSize: 17),
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(
                productDisplayData.length,
                (index) {
                  final data = productDisplayData[index];
                  final product = data.product;
                  final extrasDisVal = data.extrasDisplay;
                  final variantIno = product.variantInfo;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        minLeadingWidth: 10,
                        contentPadding: EdgeInsets.only(left: 10, right: 10),
                        visualDensity:
                            VisualDensity(horizontal: 0, vertical: -4),
                        leading: CircleAvatar(
                          radius: 13,
                          backgroundColor: Color(COLOR_PRIMARY),
                          child: Text(
                            '${product.quantity}',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                          product.name,
                          style: TextStyle(
                              color: isDarkMode(context)
                                  ? Colors.white
                                  : Color(0XFF333333),
                              fontSize: 18,
                              letterSpacing: 0.5,
                              fontFamily: 'Poppinsr'),
                        ),
                        trailing: Text(
                          amountShow(
                              amount: double.parse((product
                                              .extrasPrice!.isNotEmpty &&
                                          double.parse(product.extrasPrice!) !=
                                              0.0)
                                      ? (double.parse(product.extrasPrice!) +
                                              double.parse(product.price))
                                          .toString()
                                      : product.price)
                                  .toString()),
                          style: TextStyle(
                              color: isDarkMode(context)
                                  ? Colors.grey.shade200
                                  : Color(0XFF333333),
                              fontSize: 17,
                              letterSpacing: 0.5,
                              fontFamily: 'Poppinsr'),
                        ),
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
                      SizedBox(
                        height: 10,
                      ),
                      Container(
                        margin: EdgeInsets.only(left: 55, right: 10),
                        child: extrasDisVal.isEmpty
                            ? Container()
                            : Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  extrasDisVal,
                                  style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey,
                                      fontFamily: 'Poppinsr'),
                                ),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Center(
                child: Text(
                  'Total : ' + amountShow(amount: total.toString()),
                  style: TextStyle(
                      color: Color(COLOR_PRIMARY), fontWeight: FontWeight.bold),
                ),
              ),
            ),
            SizedBox(
              height: 10,
            ),
          ],
        ),
      ),
    );
  }

  //final audioPlayer = AudioPlayer(playerId: "playerId");
  bool isPlaying = false;

  //playSound() async {
  //  final path = await rootBundle
  //      .load("assets/audio/mixkit-happy-bells-notification-937.mp3");

  //  //audioPlayer.setSourceBytes(path.buffer.asUint8List());
  //  //audioPlayer.setReleaseMode(ReleaseMode.loop);
  //  //audioPlayer.setSourceUrl(url);
  ////  audioPlayer.play(BytesSource(path.buffer.asUint8List()),
  ////      volume: 15,
  ////      ctx: AudioContext(
  ////          android: AudioContextAndroid(
  ////              contentType: AndroidContentType.music,
  ////              isSpeakerphoneOn: true,
  //              stayAwake: true,
  //              usageType: AndroidUsageType.alarm,
  //              audioFocus: AndroidAudioFocus.gainTransient),
  //          iOS: AudioContextIOS(
  //              category: AVAudioSessionCategory.playback, options: {})));
  //}
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
