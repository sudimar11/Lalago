/// Pre-set quick messages for rider-restaurant communication.
class QuickMessages {
  QuickMessages._();

  static const Map<String, String> riderToRestaurant = {
    'on_my_way': 'On my way to your restaurant',
    'arriving_in_5': 'Arriving in 5 minutes',
    'arriving_in_2': 'Arriving in 2 minutes',
    'here_for_pickup': "I'm here for pickup",
    'running_late': 'Running a few minutes late',
    'need_help': 'Need assistance with pickup',
  };

  static const Map<String, String> restaurantToRider = {
    'order_almost_ready': 'Order is almost ready',
    'ready_for_pickup': 'Order ready for pickup',
    'please_wait_5': 'Please wait 5 more minutes',
    'go_to_counter': 'Please go to counter 2',
    'issue_with_order': "There's an issue with the order",
  };

  static String getMessage(String key, String senderType) {
    if (senderType == 'rider') {
      return riderToRestaurant[key] ?? key;
    }
    return restaurantToRider[key] ?? key;
  }

  static List<String> getKeys(String senderType) {
    if (senderType == 'rider') {
      return riderToRestaurant.keys.toList();
    }
    return restaurantToRider.keys.toList();
  }
}
