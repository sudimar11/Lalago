class NotificationPreferences {
  final bool orderNotificationsEnabled;
  final bool earningNotificationsEnabled;
  final bool performanceNotificationsEnabled;
  final bool checkoutRemindersEnabled;

  const NotificationPreferences({
    this.orderNotificationsEnabled = true,
    this.earningNotificationsEnabled = true,
    this.performanceNotificationsEnabled = true,
    this.checkoutRemindersEnabled = true,
  });

  Map<String, dynamic> toJson() => {
        'orderNotificationsEnabled': orderNotificationsEnabled,
        'earningNotificationsEnabled': earningNotificationsEnabled,
        'performanceNotificationsEnabled': performanceNotificationsEnabled,
        'checkoutRemindersEnabled': checkoutRemindersEnabled,
      };

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) =>
      NotificationPreferences(
        orderNotificationsEnabled:
            json['orderNotificationsEnabled'] as bool? ?? true,
        earningNotificationsEnabled:
            json['earningNotificationsEnabled'] as bool? ?? true,
        performanceNotificationsEnabled:
            json['performanceNotificationsEnabled'] as bool? ?? true,
        checkoutRemindersEnabled:
            json['checkoutRemindersEnabled'] as bool? ?? true,
      );
}

