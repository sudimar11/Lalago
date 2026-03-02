import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/User.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/gemini_test_service.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/localDatabase.dart';

class SettingsScreen extends StatefulWidget {
  final User user;

  const SettingsScreen({Key? key, required this.user}) : super(key: key);

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late User user;

  late CartDatabase cartDatabase;

  late bool pushNewMessages, orderUpdates, newArrivals, promotions;
  late bool ashRecommendations, ashReorderReminders, ashHungerReminders;
  late bool ashCartReminders;
  late bool autoRetryFailedOrders, allowAlternativeSuggestions;
  String? backupPaymentMethod;
  late int maxRetryAttempts;
  late bool quietHoursEnabled;
  late int quietHoursStart;
  late int quietHoursEnd;
  late String preferredLanguage;
  int cartCount = 0;

  @override
  void initState() {
    super.initState();
    user = widget.user;
    pushNewMessages = user.settings.pushNewMessages;
    orderUpdates = user.settings.orderUpdates;
    newArrivals = user.settings.newArrivals;
    promotions = user.settings.promotions;
    ashRecommendations = user.settings.ashRecommendations;
    ashReorderReminders = user.settings.ashReorderReminders;
    ashHungerReminders = user.settings.ashHungerReminders;
    ashCartReminders = user.settings.ashCartReminders;
    autoRetryFailedOrders = user.settings.autoRetryFailedOrders;
    allowAlternativeSuggestions = user.settings.allowAlternativeSuggestions;
    backupPaymentMethod = user.settings.backupPaymentMethod;
    maxRetryAttempts = user.settings.maxRetryAttempts;
    quietHoursEnabled = user.settings.quietHoursEnabled;
    quietHoursStart = user.settings.quietHoursStart;
    quietHoursEnd = user.settings.quietHoursEnd;
    preferredLanguage = user.settings.preferredLanguage;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    cartDatabase = Provider.of<CartDatabase>(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: null,
      body: SingleChildScrollView(
        child: Builder(
            builder: (buildContext) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(
                          right: 16.0, left: 16, top: 16, bottom: 8),
                      child: Text(
                        'Push Notifications',
                        style: TextStyle(
                            color: isDarkMode(context)
                                ? Colors.white54
                                : Colors.black54,
                            fontSize: 18),
                      ),
                    ),
                    Material(
                      elevation: 2,
                      color:
                          isDarkMode(context) ? Colors.black12 : Colors.white,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // SwitchListTile.adaptive(
                          //     activeColor: Color(COLOR_ACCENT),
                          //     title: Text(
                          //       'Allow Push Notifications',
                          //       style: TextStyle(
                          //         fontSize: 16,
                          //         color: isDarkMode(context) ? Colors.white : Colors.black,
                          //       ),
                          //     ),
                          //     value: pushNewMessages,
                          //     onChanged: (bool newValue) {
                          //       pushNewMessages = newValue;
                          //       setState(() {});
                          //     }),
                          SwitchListTile.adaptive(
                              activeColor: Color(COLOR_ACCENT),
                              title: Text(
                                'Order Updates',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: isDarkMode(context)
                                      ? Colors.white
                                      : Colors.black,
                                ),
                              ),
                              value: orderUpdates,
                              onChanged: (bool newValue) {
                                orderUpdates = newValue;
                                setState(() {});
                              }),
                          // SwitchListTile.adaptive(
                          //     activeColor: Color(COLOR_ACCENT),
                          //     title: Text(
                          //       'New Arrivals',
                          //       style: TextStyle(
                          //          fontSize: 16,
                          //         color: isDarkMode(context)
                          //             ? Colors.white
                          //             : Colors.black,
                          //       ),
                          //     ),
                          //     value: newArrivals,
                          //     onChanged: (bool newValue) {
                          //       newArrivals = newValue;
                          //       setState(() {});
                          //     }),
                          SwitchListTile.adaptive(
                              activeColor: Color(COLOR_ACCENT),
                              title: Text(
                                'Promotions',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: isDarkMode(context)
                                      ? Colors.white
                                      : Colors.black,
                                ),
                              ),
                              value: promotions,
                              onChanged: (bool newValue) {
                                promotions = newValue;
                                setState(() {});
                              }),
                          SwitchListTile.adaptive(
                              activeColor: Color(COLOR_ACCENT),
                              title: Text(
                                'Ash Recommendations',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: isDarkMode(context)
                                      ? Colors.white
                                      : Colors.black,
                                ),
                              ),
                              subtitle: Text(
                                'Personalized food suggestions',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDarkMode(context)
                                      ? Colors.white54
                                      : Colors.black54,
                                ),
                              ),
                              value: ashRecommendations,
                              onChanged: (bool newValue) {
                                ashRecommendations = newValue;
                                setState(() {});
                              }),
                          SwitchListTile.adaptive(
                              activeColor: Color(COLOR_ACCENT),
                              title: Text(
                                'Ash Reorder Reminders',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: isDarkMode(context)
                                      ? Colors.white
                                      : Colors.black,
                                ),
                              ),
                              value: ashReorderReminders,
                              onChanged: (bool newValue) {
                                ashReorderReminders = newValue;
                                setState(() {});
                              }),
                          SwitchListTile.adaptive(
                              activeColor: Color(COLOR_ACCENT),
                              title: Text(
                                'Ash Hunger Reminders',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: isDarkMode(context)
                                      ? Colors.white
                                      : Colors.black,
                                ),
                              ),
                              value: ashHungerReminders,
                              onChanged: (bool newValue) {
                                ashHungerReminders = newValue;
                                setState(() {});
                              }),
                          SwitchListTile.adaptive(
                              activeColor: Color(COLOR_ACCENT),
                              title: Text(
                                'Ash Cart Reminders',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: isDarkMode(context)
                                      ? Colors.white
                                      : Colors.black,
                                ),
                              ),
                              subtitle: Text(
                                'Reminders to complete your pending cart',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDarkMode(context)
                                      ? Colors.white54
                                      : Colors.black54,
                                ),
                              ),
                              value: ashCartReminders,
                              onChanged: (bool newValue) {
                                ashCartReminders = newValue;
                                setState(() {});
                              }),
                          ListTile(
                            title: Text(
                              'Notification language',
                              style: TextStyle(
                                fontSize: 16,
                                color: isDarkMode(context)
                                    ? Colors.white
                                    : Colors.black,
                              ),
                            ),
                            subtitle: Text(
                              'Language for Ash notifications',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDarkMode(context)
                                    ? Colors.white54
                                    : Colors.black54,
                              ),
                            ),
                            trailing: DropdownButton<String>(
                              value: preferredLanguage,
                              items: const [
                                DropdownMenuItem(
                                  value: 'en',
                                  child: Text('English'),
                                ),
                                DropdownMenuItem(
                                  value: 'tl',
                                  child: Text('Tagalog'),
                                ),
                                DropdownMenuItem(
                                  value: 'tsg',
                                  child: Text('Tausug'),
                                ),
                              ],
                              onChanged: (String? value) {
                                if (value != null) {
                                  setState(() => preferredLanguage = value);
                                }
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                                right: 16, left: 16, top: 16, bottom: 8),
                            child: Text(
                              'Order Recovery',
                              style: TextStyle(
                                color: isDarkMode(context)
                                    ? Colors.white54
                                    : Colors.black54,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          Material(
                            elevation: 2,
                            color: isDarkMode(context)
                                ? Colors.black12
                                : Colors.white,
                            child: Column(
                              children: [
                                SwitchListTile.adaptive(
                                    activeColor: Color(COLOR_ACCENT),
                                    title: Text(
                                      'Auto-Retry Failed Orders',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: isDarkMode(context)
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Retry with backup payment when payment fails',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDarkMode(context)
                                            ? Colors.white54
                                            : Colors.black54,
                                      ),
                                    ),
                                    value: autoRetryFailedOrders,
                                    onChanged: (bool newValue) {
                                      autoRetryFailedOrders = newValue;
                                      setState(() {});
                                    }),
                                SwitchListTile.adaptive(
                                    activeColor: Color(COLOR_ACCENT),
                                    title: Text(
                                      'Show Alternatives',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: isDarkMode(context)
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Get suggestions when items are unavailable',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDarkMode(context)
                                            ? Colors.white54
                                            : Colors.black54,
                                      ),
                                    ),
                                    value: allowAlternativeSuggestions,
                                    onChanged: (bool newValue) {
                                      allowAlternativeSuggestions = newValue;
                                      setState(() {});
                                    }),
                                if (autoRetryFailedOrders) ...[
                                  ListTile(
                                    title: Text(
                                      'Backup Payment Method',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: isDarkMode(context)
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                    trailing: DropdownButton<String?>(
                                      value: backupPaymentMethod,
                                      hint: const Text('None'),
                                      items: const [
                                        DropdownMenuItem(
                                            value: null, child: Text('None')),
                                        DropdownMenuItem(
                                            value: 'cod',
                                            child: Text('Cash on Delivery')),
                                      ],
                                      onChanged: (String? value) {
                                        backupPaymentMethod = value;
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                  ListTile(
                                    title: Text(
                                      'Max Retry Attempts',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: isDarkMode(context)
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                    trailing: DropdownButton<int>(
                                      value: maxRetryAttempts,
                                      items: [1, 2, 3, 5]
                                          .map((i) => DropdownMenuItem(
                                              value: i, child: Text('$i')))
                                          .toList(),
                                      onChanged: (int? value) {
                                        if (value != null) {
                                          maxRetryAttempts = value;
                                          setState(() {});
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          SwitchListTile.adaptive(
                              activeColor: Color(COLOR_ACCENT),
                              title: Text(
                                'Quiet Hours',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: isDarkMode(context)
                                      ? Colors.white
                                      : Colors.black,
                                ),
                              ),
                              subtitle: Text(
                                'Don\'t send notifications during these hours',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDarkMode(context)
                                      ? Colors.white54
                                      : Colors.black54,
                                ),
                              ),
                              value: quietHoursEnabled,
                              onChanged: (bool newValue) {
                                setState(() {
                                  quietHoursEnabled = newValue;
                                });
                              }),
                          if (quietHoursEnabled)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'From',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDarkMode(context)
                                                ? Colors.white54
                                                : Colors.black54,
                                          ),
                                        ),
                                        DropdownButton<int>(
                                          value: quietHoursStart,
                                          isExpanded: true,
                                          items: List.generate(
                                            24,
                                            (i) => DropdownMenuItem<int>(
                                              value: i,
                                              child: Text('$i:00'),
                                            ),
                                          ),
                                          onChanged: (int? value) {
                                            if (value != null) {
                                              setState(() {
                                                quietHoursStart = value;
                                              });
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'To',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDarkMode(context)
                                                ? Colors.white54
                                                : Colors.black54,
                                          ),
                                        ),
                                        DropdownButton<int>(
                                          value: quietHoursEnd,
                                          isExpanded: true,
                                          items: List.generate(
                                            24,
                                            (i) => DropdownMenuItem<int>(
                                              value: i,
                                              child: Text('$i:00'),
                                            ),
                                          ),
                                          onChanged: (int? value) {
                                            if (value != null) {
                                              setState(() {
                                                quietHoursEnd = value;
                                              });
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 32.0, bottom: 16),
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(minWidth: double.infinity),
                        child: Material(
                          elevation: 2,
                          color: isDarkMode(context)
                              ? Colors.black12
                              : Colors.white,
                          child: CupertinoButton(
                            padding: const EdgeInsets.all(12.0),
                            onPressed: () async {
                              showProgress(
                                  context, 'Saving changes...', true);
                              user.settings.pushNewMessages = pushNewMessages;
                              user.settings.orderUpdates = orderUpdates;
                              user.settings.newArrivals = newArrivals;
                              user.settings.promotions = promotions;
                              user.settings.ashRecommendations =
                                  ashRecommendations;
                              user.settings.ashReorderReminders =
                                  ashReorderReminders;
                              user.settings.ashHungerReminders =
                                  ashHungerReminders;
                              user.settings.ashCartReminders =
                                  ashCartReminders;
                              user.settings.autoRetryFailedOrders =
                                  autoRetryFailedOrders;
                              user.settings.allowAlternativeSuggestions =
                                  allowAlternativeSuggestions;
                              user.settings.backupPaymentMethod =
                                  backupPaymentMethod;
                              user.settings.maxRetryAttempts =
                                  maxRetryAttempts;
                              user.settings.quietHoursEnabled =
                                  quietHoursEnabled;
                              user.settings.quietHoursStart =
                                  quietHoursStart;
                              user.settings.quietHoursEnd =
                                  quietHoursEnd;
                              user.settings.preferredLanguage =
                                  preferredLanguage;
                              User? updateUser =
                                  await FireStoreUtils.updateCurrentUser(user);
                              hideProgress();
                              if (updateUser != null) {
                                this.user = updateUser;
                                MyAppState.currentUser = user;
                                ScaffoldMessenger.of(buildContext)
                                    .showSnackBar(SnackBar(
                                        duration: Duration(seconds: 3),
                                        content: Text(
                                          'Settings saved successfully',
                                          style: TextStyle(fontSize: 17),
                                        )));
                              }
                            },
                            child: Text(
                              'save',
                              style: TextStyle(
                                  fontSize: 18, color: Color(COLOR_PRIMARY)),
                            ),
                            color: isDarkMode(context)
                                ? Colors.black12
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                          right: 16.0, left: 16, top: 16, bottom: 8),
                      child: Text(
                        'AI',
                        style: TextStyle(
                            color: isDarkMode(context)
                                ? Colors.white54
                                : Colors.black54,
                            fontSize: 18),
                      ),
                    ),
                    Material(
                      elevation: 2,
                      color: isDarkMode(context)
                          ? Colors.black12
                          : Colors.white,
                      child: ListTile(
                        title: Text(
                          'Test Gemini AI',
                          style: TextStyle(
                            fontSize: 16,
                            color: isDarkMode(context)
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                        trailing: Icon(
                          Icons.psychology,
                          color: Color(COLOR_ACCENT),
                        ),
                        onTap: () async {
                          showProgress(
                              buildContext, 'Calling Gemini AI...', true);
                          try {
                            final text = await testGemini();
                            hideProgress();
                            if (!mounted) return;
                            final msg = text ?? 'No response';
                            showDialog(
                              context: buildContext,
                              builder: (ctx) => AlertDialog(
                                title: Text('Gemini Response'),
                                content: SingleChildScrollView(
                                  child: SelectableText(msg),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: Text('OK'),
                                  ),
                                ],
                              ),
                            );
                          } catch (e, st) {
                            hideProgress();
                            if (!mounted) return;
                            showDialog(
                              context: buildContext,
                              builder: (ctx) => AlertDialog(
                                title: Text('Error'),
                                content: SingleChildScrollView(
                                  child: SelectableText.rich(
                                    TextSpan(
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 14,
                                      ),
                                      children: [
                                        TextSpan(text: e.toString()),
                                        TextSpan(
                                          text: '\n\n$st',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: Text('OK'),
                                  ),
                                ],
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                )),
      ),
    );
  }
}
