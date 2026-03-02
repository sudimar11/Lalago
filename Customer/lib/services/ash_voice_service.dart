/// Ash voice patterns for in-app chat and UI.
/// Keeps Ash's personality consistent across the Customer app.
class AshVoiceService {
  static String getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Good morning!';
    if (hour >= 12 && hour < 18) return 'Good afternoon!';
    if (hour >= 18 && hour < 22) return 'Good evening!';
    return 'Hi there!';
  }

  static String getIntro(String? userName) {
    final namePart = userName != null && userName.isNotEmpty ? ' $userName' : '';
    return '${getGreeting()} I\'m Ash, your Lalago food assistant. '
        'How can I help you today?';
  }

  /// Returns a list of loading messages to cycle through.
  static List<String> getLoadingMessages(String query) {
    final primary = getLoadingMessage(query);
    final fallbacks = [
      'Ash is checking restaurants...',
      'Ash is almost ready...',
      'Ash is preparing your recommendations...',
    ];
    return [primary, ...fallbacks];
  }

  static String getLoadingMessage(String query) {
    final q = query.toLowerCase();

    if (q.contains('seafood') ||
        q.contains('fish') ||
        q.contains('shrimp') ||
        q.contains('crab')) {
      return 'Ash is checking which seafood is freshest today...';
    }
    if (q.contains('pizza')) {
      return 'Ash is looking for the best pizza places...';
    }
    if (q.contains('burger')) {
      return 'Ash is grilling up some options...';
    }
    if (q.contains('milktea') || q.contains('tea') || q.contains('boba')) {
      return 'Ash is brewing some drink options...';
    }
    if (q.contains('pastil') ||
        q.contains('satti') ||
        q.contains('pyanggang') ||
        q.contains('tiyula') ||
        q.contains('juring') ||
        q.contains('putli')) {
      return 'Ash is asking locals for the best Tausug dishes...';
    }
    if (q.contains('near me') || q.contains('nearby') || q.contains('close')) {
      return 'Ash is finding restaurants near you...';
    }
    if (q.contains('popular') ||
        q.contains('trending') ||
        q.contains('most ordered')) {
      return 'Ash is checking what\'s trending today...';
    }
    if (q.contains('order') ||
        q.contains('status') ||
        q.contains('where is')) {
      return 'Ash is tracking your order...';
    }
    if (q.contains('book') ||
        q.contains('table') ||
        q.contains('reservation')) {
      return 'Ash is checking table availability...';
    }

    return 'Ash is thinking...';
  }

  static String getThankYou() {
    const thanks = [
      'You\'re welcome! Happy to help!',
      'Anytime! That\'s what I\'m here for.',
      'Glad I could help! Enjoy your meal!',
      'My pleasure! Let me know if you need anything else.',
    ];
    return thanks[DateTime.now().second % thanks.length];
  }

  static String getErrorMessage() {
    const errors = [
      'Oops! Something went wrong. Want to try that again?',
      'Hmm, I had trouble with that. Could you rephrase?',
      'Sorry about that! Let\'s try again.',
      'Technical hiccup! What were you looking for?',
    ];
    return errors[DateTime.now().second % errors.length];
  }
}
