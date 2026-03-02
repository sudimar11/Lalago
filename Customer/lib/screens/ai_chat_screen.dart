import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/services/ai_cart_service.dart';
import 'package:foodie_customer/services/word_correction_service.dart';
import 'package:foodie_customer/services/tausug_teachings_service.dart';
import 'package:foodie_customer/services/ai_tool_declarations.dart';
import 'package:foodie_customer/services/ai_chat_tool_handler.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/localDatabase.dart';
import 'package:foodie_customer/screens/ai_chat_cards.dart';
import 'package:foodie_customer/services/ash_voice_service.dart';
import 'package:foodie_customer/widgets/ash_avatar.dart';
import 'package:foodie_customer/widgets/closed_restaurant_card.dart';

/// Food-themed loading indicator for AI thinking state.
class FoodLoadingIndicator extends StatelessWidget {
  const FoodLoadingIndicator({
    Key? key,
    required this.message,
  }) : super(key: key);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRect(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
          SizedBox(
            width: 60,
            height: 40,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  child: Icon(
                    Icons.rice_bowl,
                    color: Color(COLOR_PRIMARY),
                    size: 28,
                  ),
                ),
                Positioned(
                  left: 24,
                  child: Icon(
                    Icons.emoji_food_beverage,
                    color: Color(COLOR_PRIMARY).withValues(alpha: 0.8),
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const TypingDots(),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
                fontSize: 13,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        ),
      ),
    );
  }
}

/// Animated typing dots.
class TypingDots extends StatefulWidget {
  const TypingDots({Key? key}) : super(key: key);

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animations = List.generate(3, (index) {
      return Tween<double>(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(
            index * 0.2,
            0.8 + index * 0.1,
            curve: Curves.easeInOut,
          ),
        ),
      );
    });
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _animations[index],
          builder: (context, child) {
            return Container(
              width: 8 * _animations[index].value,
              height: 8 * _animations[index].value,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: Colors.grey[500],
                shape: BoxShape.circle,
              ),
            );
          },
        );
      }),
    );
  }
}

class AiChatScreen extends StatefulWidget {
  @override
  _AiChatScreenState createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _greetingAdded = false;
  bool _disposed = false;

  Timer? _loadingMessageTimer;
  int _currentMessageIndex = 0;
  List<String> _currentMessageSet = [];

  late ChatSession _chat;
  late AiChatToolHandler _toolHandler;
  late AiCartService _aiCartService;
  int _buildCount = 0;

  /// Session cache: Tausug word -> English meaning (taught this session).
  final Map<String, String> _sessionTeachings = {};

  /// True when processing a teaching message until confirmation is sent.
  bool _isInLearningMode = false;

  /// Total teachings + corrections contributed by current user.
  int _teachingCount = 0;

  @override
  void initState() {
    debugPrint('🟢 [LIFECYCLE] AiChatScreen initState START');
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_greetingAdded && mounted) {
        setState(() {
          _messages.add(ChatMessage(
            type: MessageType.text,
            text: AshVoiceService.getIntro(MyAppState.currentUser?.firstName),
            isUser: false,
            timestamp: DateTime.now(),
          ));
          _greetingAdded = true;
        });
      }
    });
    debugPrint('🟢 [LIFECYCLE] AiChatScreen initState COMPLETE');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_chatInitialized) {
      _chatInitialized = true;
      _initChat();
    }
    _loadTeachingCount();
  }

  Future<void> _loadTeachingCount() async {
    final userId = MyAppState.currentUser?.userID ??
        FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    try {
      final teachings = await TausugTeachingsService.getTeachingCount(userId);
      final corrections =
          await WordCorrectionService.getCorrectionCount(userId);
      if (!_disposed && mounted) {
        setState(() => _teachingCount = teachings + corrections);
      }
    } catch (_) {}
  }

  bool _chatInitialized = false;

  // Test queries for Tausug support:
  // - "Hawnu kaw maka pastil?" (Where can I get pastil?)
  // - "Unu in mananam na pyanggang?" (What tasty grilled chicken?)
  // - "Mangaun aku satti" (I want to eat satti)
  // - "May tiyulah itum kaw?" (Do you have black soup?)
  // - "Bang may pastil, pila?" (If there's pastil, how much?)
  // - "Amuin add to cart in satti" (Please add satti to cart)

  // TAUSUG LANGUAGE SUPPORT - IMPORTANT NOTES:
  // 1. Tausug is NOT an officially supported language in Gemini
  // 2. Filipino/Tagalog IS supported and works well
  // 3. For Tausug queries, we map common food terms to English/Tagalog
  // 4. Response quality may be lower than English/Tagalog
  // 5. Consider collecting user feedback to improve Tausug understanding

  static const _tausugWords = [
    'tiyula', 'tiula', 'pastil', 'pyanggang', 'tiyulah itum',
    'satti', 'juring', 'lumpia', 'putli', 'durul', 'kaun',
    'mangaun', 'hawnu', 'hawnu kaw', 'unu', 'unu in', 'siya',
    'aku', 'kita', 'niya', 'bang', 'pila', 'masarap', 'mananam',
    'mapa\'it', 'maslum', 'malimu', 'maasin', 'malara',
  ];

  bool _containsTausug(String text) {
    final lower = text.toLowerCase();
    return _tausugWords.any((word) => lower.contains(word));
  }

  List<String> _detectTausugWords(String text) {
    final lower = text.toLowerCase();
    return _tausugWords.where((w) => lower.contains(w)).toList();
  }

  bool _isHighConfidenceTausug(String text) {
    final words = text.toLowerCase().split(RegExp(r'\s+'));
    if (words.isEmpty) return false;
    int matchCount = 0;
    for (final word in words) {
      if (_tausugWords.any((tw) =>
          word.contains(tw) || tw.contains(word))) {
        matchCount++;
      }
    }
    return matchCount / words.length > 0.3;
  }

  String _buildSystemPrompt() {
    final now = DateTime.now();
    final currentTime = DateFormat('h:mm a').format(now);
    final currentDay = DateFormat('EEEE', 'en_US').format(now);

    return '''
You are Ash, a friendly and helpful food assistant for the Lalago app. Your name is Ash – short, approachable, and easy to remember.

CURRENT TIME: $currentDay at $currentTime (local time)

IMPORTANT RULES FOR ORDERING:
1. Before adding items to cart, call check_restaurant_status with the restaurant's vendorId to verify it is open.
2. Never add items from a closed restaurant. If closed, tell the user and show today's hours.

You serve users in the Philippines including Tausug-speaking communities in Sulu. You can:
- Recommend restaurants and dishes based on available data
- Place/manage orders (add to cart, apply coupons)
- Track orders (check status, ETA)
- Handle account/membership queries
- Book tables (always confirm first)
- Answer customer support questions about delivery, refunds, and policies

LANGUAGE GUIDELINES:
- If the user asks in English, respond in English.
- If the user asks in Tagalog/Filipino, respond in Tagalog.
- If the user asks in Tausug (or mixes Tausug with other languages), do your best to understand and respond helpfully using Tagalog/English.

Always confirm before booking a table. For orders, add items to cart but let the user complete checkout in the app.

Identify yourself as Ash when appropriate (e.g., "Hi, I'm Ash! How can I help you today?")
''';
  }

  List<String> _getLoadingMessagesForQuery(String query) {
    final q = query.toLowerCase();

    if (q.contains('seafood') ||
        q.contains('fish') ||
        q.contains('shrimp') ||
        q.contains('crab')) {
      return [
        'Tagad kaw mamingit naa kita...'
        'Kitaun ta maraw bang in nakawah malingkat da...'
        'Mang lawag naa kita bang awn pa marayaw landuh...'
        'Kitaun ta naa bang unu naman in marayaw ha adlaw yan...'
        'Nag hambuk-hambuuk pa sin mga malingkat para kaymu...',
      ];
    }

    if (q.contains('pizza')) {
      return [
        'Tagad ampa kita mag addun...',
        'Butangan ta naa sin mga katagihan mo...',
        'Lawagun ta naa hawnu pa in mga pag-hihinangan...',
        'Lawagun ko pa unu in malandag pizza die ha sug...',
        'Masuuk na tuud, mag slice da kuman...',
      ];
    }

    if (q.contains('burger')) {
      return [
        'Mag tapa sadja hangkarae...',
        'Kitaun ta naa bang maraw da in palaman...',
        'Butangan ta naa sauce kaymu lasa...',
        'Lawagun ko naa in masuuk pag hinangan burger die...',
        'Tagad mag serve da kuman mapasuh pa...',
      ];
    }

    if (q.contains('milktea') ||
        q.contains('tea') ||
        q.contains('boba')) {
      return [
        'Tagad mag timpla naa kita...',
        'Nag butang na mga lamud...',
        'Yari na nag gaw-gaw...',
        'Kitaan ta naa kaw mga ukab tinda...',
        'Masuuk na kaw maka inum tagad...',
      ];
    }

    if (q.contains('near me') ||
        q.contains('nearby') ||
        q.contains('close')) {
      return [
        'Nag lalawag pa sin restaurants masuuk kaymu...',
        'Checking who\'s closest to your location...',
        'Looking at their ratings and reviews...',
        'Seeing what\'s popular nearby...',
        'Almost ready with nearby options...',
      ];
    }

    if (q.contains('popular') ||
        q.contains('trending') ||
        q.contains('most ordered')) {
      return [
        'Checking what\'s trending today...',
        'Counting today\'s orders...',
        'Finding customer favorites...',
        'Looking at popular dishes right now...',
        'Almost done with the top picks...',
      ];
    }

    if (q.contains('order') ||
        q.contains('status') ||
        q.contains('where is')) {
      return [
        'Tracking your order...',
        'Checking with the restaurant...',
        'Looking up delivery status...',
        'Seeing when it will arrive...',
        'Almost there with your update...',
      ];
    }

    if (q.contains('book') ||
        q.contains('table') ||
        q.contains('reservation')) {
      return [
        'Checking table availability...',
        'Looking at restaurant schedules...',
        'Finding the best time for you...',
        'Confirming your booking options...',
        'Almost ready to reserve...',
      ];
    }

    if (q.contains('pastil') ||
        q.contains('satti') ||
        q.contains('pyanggang') ||
        q.contains('tiyula') ||
        q.contains('juring') ||
        q.contains('putli')) {
      return [
        'Looking for authentic Tausug dishes...',
        'Checking which restaurants serve this...',
        'Asking locals for recommendations...',
        'Finding the best spots in town...',
        'Almost ready with traditional options...',
      ];
    }

    return [
      'Hatihun ku naa maraw in kabtangan mu...',
      'Lawagun ku naa ha mga restaurants...',
      'Nag check na aku sin mga menu ha restaurants, tagad...',
      'Lawagun ko da kuman hawnu in masarap...',
      'Tagad masuuk na maubus...',
    ];
  }

  void _initChat() {
    debugPrint('🔵 [INIT_CHAT] _initChat START');
    try {
      final cartDatabase = Provider.of<CartDatabase>(context, listen: false);
      _aiCartService = AiCartService(cartDatabase: cartDatabase);
      _toolHandler = AiChatToolHandler(
        userId: MyAppState.currentUser?.userID,
        aiCartService: _aiCartService,
        cartDatabase: cartDatabase,
        context: context,
      );
      debugPrint('🔵 [INIT_CHAT] Tool handler created, userId: ${MyAppState.currentUser?.userID}');

      final systemPrompt = _buildSystemPrompt();
      final model = FirebaseAI.googleAI().generativeModel(
        model: 'gemini-2.5-flash-lite',
        tools: [Tool.functionDeclarations(aiToolDeclarations)],
        systemInstruction: Content.system(systemPrompt),
      );
      _chat = model.startChat();
      debugPrint('🔵 [INIT_CHAT] _initChat COMPLETE - chat session started');
    } catch (e, st) {
      debugPrint('❌ [ERROR] _initChat failed: $e');
      debugPrint('💥 [STACK] $st');
      rethrow;
    }
  }

  bool _isSimpleGreeting(String message) {
    final lower = message.trim().toLowerCase();
    const greetings = [
      'hi', 'hello', 'hey', 'good morning', 'good afternoon', 'good evening',
      'howdy', 'greetings', 'sup', 'what\'s up', 'how are you', 'kamusta',
      'musta', 'hello po', 'hi po', 'musta na', 'good pm', 'good am',
      'magandang umaga', 'magandang hapon', 'magandang gabi',
    ];
    if (greetings.contains(lower)) return true;
    if (greetings.any((g) => lower.startsWith(g) && lower.length < 25)) {
      return true;
    }
    if (lower.contains('thank') && lower.length < 30) return true;
    if (lower.contains('bye') && lower.length < 25) return true;
    return false;
  }

  String _getGreetingResponse(String userMessage) {
    final lower = userMessage.toLowerCase();
    if (lower.contains('kamusta') || lower.contains('musta')) {
      return 'Mustang maganda! Ako si Ash, ang iyong Lalago assistant. '
          'Paano kita matutulungan ngayon?';
    }
    if (lower.contains('good morning') || lower.contains('magandang umaga')) {
      return 'Good morning! Ash here. What can I help you with today?';
    }
    if (lower.contains('good afternoon') || lower.contains('magandang hapon')) {
      return 'Good afternoon! This is Ash. How may I assist you?';
    }
    if (lower.contains('good evening') || lower.contains('magandang gabi')) {
      return 'Good evening! Ash here. Looking for food recommendations?';
    }
    if (lower.contains('thank')) {
      return 'You\'re welcome! Let me know if you need anything else.';
    }
    if (lower.contains('bye')) {
      return 'Goodbye! Thanks for chatting. Come back anytime.';
    }
    return 'Hello! I\'m Ash, your Lalago assistant. How can I help you today?';
  }

  void _sendMessage() async {
    if (_controller.text.trim().isEmpty) return;

    final userQuery = _controller.text.trim();
    if (_isSimpleGreeting(userQuery)) {
      debugPrint('⚡ [FAST PATH] Chit-chat detected, responding instantly');
      setState(() {
        _messages.add(ChatMessage(
          type: MessageType.text,
          text: userQuery,
          isUser: true,
          timestamp: DateTime.now(),
        ));
        _isLoading = true;
      });
      _controller.clear();
      await Future.delayed(const Duration(milliseconds: 500));
      if (!_disposed && mounted) {
        setState(() {
          _messages.add(ChatMessage(
            type: MessageType.text,
            text: _getGreetingResponse(userQuery),
            isUser: false,
            timestamp: DateTime.now(),
          ));
          _isLoading = false;
        });
      }
      debugPrint('⏱️ Fast-path response completed');
      return;
    }

    setState(() {
      _messages.add(ChatMessage(
        type: MessageType.text,
        text: userQuery,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isLoading = true;
      _currentMessageSet = AshVoiceService.getLoadingMessages(userQuery);
      _currentMessageIndex = 0;
    });
    _loadingMessageTimer?.cancel();
    _loadingMessageTimer = Timer.periodic(
      const Duration(seconds: 3),
      (timer) {
        if (!_isLoading || _disposed || !mounted) {
          timer.cancel();
          _loadingMessageTimer = null;
          return;
        }
        setState(() {
          _currentMessageIndex =
              (_currentMessageIndex + 1) % _currentMessageSet.length;
        });
      },
    );
    _controller.clear();

    final isOnline = await hasNetwork();
    if (!isOnline) {
      _loadingMessageTimer?.cancel();
      _loadingMessageTimer = null;
      if (!_disposed && mounted) {
        setState(() {
          _isLoading = false;
          _messages.add(ChatMessage(
            type: MessageType.text,
            text: 'No internet connection. Please check your network '
                'and try again.',
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
      }
      return;
    }

    try {
      debugPrint('📤 [SEND] Sending message: "$userQuery"');

      // Handle teaching messages (correction, teach, learn, X means Y)
      if (TausugTeachingsService.isTeachingMessage(userQuery)) {
        _loadingMessageTimer?.cancel();
        _loadingMessageTimer = null;
        setState(() => _isInLearningMode = true);

        final result =
            TausugTeachingsService.parseTeachingMessage(userQuery);
        if (result != null) {
          final userId = MyAppState.currentUser?.userID ??
              FirebaseAuth.instance.currentUser?.uid;
          final successText = "Salamat! I've learned that "
              "'${result.tausugWord}' means '${result.englishMeaning}'.";
          final aiIndex = _messages.length;
          if (!_disposed && mounted) {
            setState(() {
              _messages.add(ChatMessage(
                type: MessageType.text,
                text: 'Saving…',
                isUser: false,
                timestamp: DateTime.now(),
                teachingStatus: TeachingStatus.pending,
                teachingResult: result,
              ));
            });
          }
          if (userId != null) {
            try {
              final ref = await TausugTeachingsService.store(
                userId: userId,
                tausugWord: result.tausugWord,
                englishMeaning: result.englishMeaning,
              );
              _sessionTeachings[result.tausugWord] = result.englishMeaning;
              developer.log(
                '[TEACHING_SAVED] path: ${ref.path}, id: ${ref.id}',
                name: 'AiChat',
              );
              developer.log(
                '[TEACHING_SAVED] tausugWord: ${result.tausugWord}, '
                'englishMeaning: ${result.englishMeaning}',
                name: 'AiChat',
              );
              if (!_disposed && mounted) {
                setState(() {
                  _messages[aiIndex] = _messages[aiIndex].copyWith(
                    text: successText,
                    teachingStatus: TeachingStatus.saved,
                  );
                  _isInLearningMode = false;
                  _teachingCount++;
                });
              }
            } catch (e) {
              debugPrint('Error storing teaching: $e');
              if (!_disposed && mounted) {
                setState(() {
                  _messages[aiIndex] = _messages[aiIndex].copyWith(
                    text: "Couldn't save – check your connection.",
                    teachingStatus: TeachingStatus.failed,
                  );
                  _isInLearningMode = false;
                });
              }
            }
          } else {
            if (!_disposed && mounted) {
              setState(() {
                _messages[aiIndex] = _messages[aiIndex].copyWith(
                  text: 'Please log in to save teachings.',
                  teachingStatus: TeachingStatus.failed,
                );
                _isInLearningMode = false;
              });
            }
          }
        } else {
          if (!_disposed && mounted) {
            setState(() {
              _messages.add(ChatMessage(
                type: MessageType.text,
                text: "I couldn't parse that. Try: \"hawnu means where\" "
                    "or \"teach: pastil means rice wrap\".",
                isUser: false,
                timestamp: DateTime.now(),
              ));
              _isInLearningMode = false;
            });
          }
        }
        if (!_disposed && mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      final correctionHint =
          await WordCorrectionService.getCorrectionHintForQuery(userQuery);
      if (_disposed || !mounted) return;
      final teachingsHint =
          await TausugTeachingsService.getTeachingsHintForQuery(
        userQuery,
        sessionCache: _sessionTeachings,
      );
      if (_disposed || !mounted) return;
      final hints = [correctionHint, teachingsHint]
          .where((h) => h.isNotEmpty)
          .join('');
      final content = hints.isNotEmpty
          ? Content.text('$hints\n\nUser question: $userQuery')
          : Content.text(userQuery);
      debugPrint('📤 [SEND] Calling _chat.sendMessage...');
      var response = await _chat.sendMessage(content);
      if (_disposed || !mounted) return;
      String? lastToolName;
      Map<String, dynamic>? lastResult;

      int loopCount = 0;
      const int maxLoops = 10;

      while (response.functionCalls.isNotEmpty && loopCount <= maxLoops) {
        if (_disposed || !mounted) break;
        loopCount++;
        if (loopCount > maxLoops) {
          debugPrint('❌ [ERROR] Function-calling loop exceeded $maxLoops '
              'iterations - breaking out');
          break;
        }
        debugPrint('🔄 [LOOP] Iteration $loopCount, '
            '${response.functionCalls.length} function calls');

        final functionCalls = response.functionCalls.toList();
        for (final fc in functionCalls) {
          Map<String, dynamic> result;
          try {
            if (fc.name == 'book_table') {
              final details = await _toolHandler.executeTool(
                'book_table',
                _toDynamicMap(fc.args),
              );
              if (details['pendingConfirmation'] == true &&
                  !_disposed &&
                  mounted) {
                final confirmed = await _showBookingConfirmDialog(details);
                if (confirmed) {
                  result = await _toolHandler.performBookTable(
                    _toDynamicMap(fc.args),
                  );
                } else {
                  result = {'cancelled': true, 'message': 'User declined'};
                }
              } else {
                result = details;
              }
            } else {
              result = await _toolHandler.executeTool(
                fc.name,
                _toDynamicMap(fc.args),
              );
            }
          } catch (e, st) {
            debugPrint('❌ [ERROR] Tool ${fc.name} failed: $e');
            debugPrint('💥 [STACK] $st');
            rethrow;
          }
          lastToolName = fc.name;
          lastResult = result;
          if (_disposed || !mounted) break;
          response = await _chat.sendMessage(
            Content.functionResponse(fc.name, result),
          );
        }
        if (_disposed || !mounted) break;
      }

      if (!_disposed && mounted) {
        setState(() {
          final richType = _messageTypeForTool(lastToolName, lastResult);
          if (richType != null && lastResult != null) {
            final msg = (lastResult['message'] ?? '').toString();
            _messages.add(ChatMessage(
              type: richType,
              text: msg,
              data: lastResult,
              isUser: false,
              timestamp: DateTime.now(),
            ));
          }
          final text = response.text?.trim() ?? '';
          if (text.isNotEmpty) {
            _messages.add(ChatMessage(
              type: MessageType.text,
              text: text,
              isUser: false,
              timestamp: DateTime.now(),
            ));
          } else if (richType == null) {
            _messages.add(ChatMessage(
              type: MessageType.text,
              text: "Sorry, I couldn't complete that.",
              isUser: false,
              timestamp: DateTime.now(),
            ));
          }
        });
      }
    } catch (e, st) {
      debugPrint('❌ [ERROR] _sendMessage failed: $e');
      debugPrint('💥 [STACK] $st');
      final friendlyMessage = _toFriendlyError(e);
      if (!_disposed && mounted) {
        setState(() {
          _messages.add(ChatMessage(
            type: MessageType.text,
            text: friendlyMessage,
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
      }
    } finally {
      _loadingMessageTimer?.cancel();
      _loadingMessageTimer = null;
      if (!_disposed && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Map<String, dynamic> _toDynamicMap(Map<String, Object?> args) {
    return Map<String, dynamic>.from(args);
  }

  String _toFriendlyError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('socket') ||
        s.contains('connection') ||
        s.contains('network') ||
        s.contains('failed host lookup') ||
        s.contains('no internet')) {
      return 'No internet connection. Please check your network and try again.';
    }
    if (s.contains('timeout') || s.contains('timed out')) {
      return 'Request timed out. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  MessageType? _messageTypeForTool(
    String? toolName,
    Map<String, dynamic>? result,
  ) {
    if (toolName == null || result == null) return null;
    if (toolName == 'add_products_to_cart' &&
        result['error'] == 'cannot_add_closed') {
      return MessageType.closedRestaurant;
    }
    if (result['error'] != null &&
        result['cancelled'] != true &&
        result['success'] != true) {
      return null;
    }
    switch (toolName) {
      case 'search_restaurants':
        return MessageType.restaurantList;
      case 'search_products':
        return MessageType.productList;
      case 'get_order_status':
        return MessageType.orderStatus;
      case 'get_active_orders':
        return MessageType.orderList;
      case 'book_table':
        return result['booking'] != null
            ? MessageType.bookingConfirmation
            : null;
      case 'apply_best_coupon':
        return MessageType.couponResult;
      case 'get_popular_items':
      case 'get_popular_items_at_restaurant':
        return MessageType.popularList;
      default:
        return null;
    }
  }

  Future<void> _saveWordCorrection(
    ChatMessage aiMessage,
    String correctionText,
  ) async {
    final userId = MyAppState.currentUser?.userID ??
        FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final aiIndex = _messages.indexOf(aiMessage);
    if (aiIndex <= 0) return;
    final userMessage = _messages[aiIndex - 1];
    if (!userMessage.isUser) return;

    final detectedWords = _detectTausugWords(userMessage.text);
    try {
      final ref = await WordCorrectionService.store(
        userId: userId,
        userQuery: userMessage.text,
        aiResponse: aiMessage.text,
        correction: correctionText,
        detectedWords: detectedWords,
      );
      developer.log(
        '[TEACHING_SAVED] word_corrections path: ${ref.path}, id: ${ref.id}',
        name: 'AiChat',
      );
      developer.log(
        '[TEACHING_SAVED] userQuery: ${userMessage.text}, '
        'correction: $correctionText, detectedWords: $detectedWords',
        name: 'AiChat',
      );
      if (!_disposed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thank you for teaching me!')),
        );
        _loadTeachingCount();
      }
    } catch (e) {
      debugPrint('Error storing word correction: $e');
    }
  }

  Future<void> _showContributionHistoryDialog() async {
    final userId = MyAppState.currentUser?.userID ??
        FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final teachings =
        await TausugTeachingsService.getRecentTeachings(userId, limit: 20);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Text('📚 '),
            Text('Your contributions ($_teachingCount total)'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: teachings.isEmpty
              ? const Text('No teachings yet. Teach Ash new words!')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: teachings.length,
                  itemBuilder: (context, i) {
                    final t = teachings[i];
                    final word = (t['tausugWord'] ?? '').toString();
                    final meaning =
                        (t['englishMeaning'] ?? '').toString();
                    return ListTile(
                      dense: true,
                      title: Text("'$word' → '$meaning'"),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _retryTeaching(int index) async {
    if (index < 0 || index >= _messages.length) return;
    final msg = _messages[index];
    final result = msg.teachingResult;
    if (result == null || msg.teachingStatus != TeachingStatus.failed) return;

    final userId = MyAppState.currentUser?.userID ??
        FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    setState(() {
      _messages[index] = msg.copyWith(
        text: 'Saving…',
        teachingStatus: TeachingStatus.pending,
      );
    });

    try {
      final ref = await TausugTeachingsService.store(
        userId: userId,
        tausugWord: result.tausugWord,
        englishMeaning: result.englishMeaning,
      );
      _sessionTeachings[result.tausugWord] = result.englishMeaning;
      developer.log(
        '[TEACHING_SAVED] path: ${ref.path}, id: ${ref.id}',
        name: 'AiChat',
      );
      developer.log(
        '[TEACHING_SAVED] tausugWord: ${result.tausugWord}, '
        'englishMeaning: ${result.englishMeaning}',
        name: 'AiChat',
      );
      if (!_disposed && mounted) {
        setState(() {
          _messages[index] = _messages[index].copyWith(
            text: "Salamat! I've learned that '${result.tausugWord}' "
                "means '${result.englishMeaning}'.",
            teachingStatus: TeachingStatus.saved,
          );
          _teachingCount++;
        });
      }
    } catch (e) {
      debugPrint('Retry teaching failed: $e');
      if (!_disposed && mounted) {
        setState(() {
          _messages[index] = _messages[index].copyWith(
            text: "Couldn't save – check your connection.",
            teachingStatus: TeachingStatus.failed,
          );
        });
      }
    }
  }

  Future<bool> _showBookingConfirmDialog(Map<String, dynamic> details) async {
    final vendorName = details['vendorName'] ?? '';
    final date = details['date'] ?? '';
    final time = details['time'] ?? '';
    final guests = details['totalGuests'] ?? 2;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Confirm table booking'),
        content: Text(
          'Book at $vendorName\n'
          'Date: $date\nTime: $time\nGuests: $guests',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(COLOR_PRIMARY),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  void dispose() {
    debugPrint('🔴 [LIFECYCLE] AiChatScreen dispose START');
    _disposed = true;
    _loadingMessageTimer?.cancel();
    _loadingMessageTimer = null;
    _controller.dispose();
    super.dispose();
    debugPrint('🔴 [LIFECYCLE] AiChatScreen dispose COMPLETE');
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute;
    return '${h > 12 ? h - 12 : (h == 0 ? 12 : h)}:'
        '${m.toString().padLeft(2, '0')} ${h >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    _buildCount++;
    if (_buildCount % 50 == 0 || _buildCount < 5) {
      debugPrint('🔄 [BUILD] AiChatScreen build #$_buildCount');
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AshAvatar(radius: 16),
            const SizedBox(width: 8),
            const Text('Ask Ash'),
          ],
        ),
        backgroundColor: Color(COLOR_PRIMARY),
        foregroundColor: Colors.white,
        actions: [
          if (_teachingCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: _showContributionHistoryDialog,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('📚', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 4),
                      Text(
                        '$_teachingCount teachings',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final isSameSender = index > 0 &&
                    _messages[index].isUser ==
                        _messages[index - 1].isUser;
                return ChatBubble(
                  message: _messages[index],
                  messageIndex: index,
                  isDark: isDark,
                  cartService: _aiCartService,
                  isSameSenderAsPrevious: isSameSender,
                  formatTime: _formatTime,
                  onCorrectionSubmitted: (correction) =>
                      _saveWordCorrection(_messages[index], correction),
                  onRetryTeaching: _retryTeaching,
                );
              },
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: _isLoading ? 60 : 0,
            child: _isLoading
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: FoodLoadingIndicator(
                      message: _currentMessageSet.isNotEmpty
                          ? _currentMessageSet[
                              _currentMessageIndex % _currentMessageSet.length]
                          : 'Ash is thinking...',
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          if (_isInLearningMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Colors.purple.shade100,
              child: Row(
                children: [
                  Text(
                    '📚 Ash is learning...',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.purple.shade900,
                    ),
                  ),
                ],
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  offset: const Offset(0, -2),
                  blurRadius: 8,
                ),
              ],
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: 'What are you craving?',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(16),
                          filled: true,
                          fillColor:
                              isDark ? Colors.grey[800] : Colors.grey[100],
                        ),
                        maxLines: null,
                        enabled: !_isLoading,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    if (_isLoading)
                      Container(
                        width: 48,
                        height: 48,
                        margin: const EdgeInsets.only(left: 8),
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(COLOR_PRIMARY),
                            ),
                          ),
                        ),
                      )
                    else
                      CircleAvatar(
                        backgroundColor: Color(COLOR_PRIMARY),
                        child: IconButton(
                          icon: const Icon(Icons.send, color: Colors.white),
                          onPressed: () {
                            if (_controller.text.trim().isNotEmpty) {
                              _sendMessage();
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum MessageType {
  text,
  restaurantList,
  productList,
  orderStatus,
  orderList,
  bookingConfirmation,
  popularList,
  couponResult,
  closedRestaurant,
}

enum TeachingStatus { pending, saved, failed }

class ChatMessage {
  final MessageType type;
  final String text;
  final dynamic data;
  final bool isUser;
  final DateTime? timestamp;
  final TeachingStatus? teachingStatus;
  final TeachingResult? teachingResult;

  ChatMessage({
    required this.type,
    required this.text,
    this.data,
    required this.isUser,
    this.timestamp,
    this.teachingStatus,
    this.teachingResult,
  });

  ChatMessage copyWith({
    MessageType? type,
    String? text,
    dynamic data,
    bool? isUser,
    DateTime? timestamp,
    TeachingStatus? teachingStatus,
    TeachingResult? teachingResult,
  }) {
    return ChatMessage(
      type: type ?? this.type,
      text: text ?? this.text,
      data: data ?? this.data,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      teachingStatus: teachingStatus ?? this.teachingStatus,
      teachingResult: teachingResult ?? this.teachingResult,
    );
  }
}

class ChatBubble extends StatefulWidget {
  const ChatBubble({
    Key? key,
    required this.message,
    this.messageIndex = -1,
    this.isDark = false,
    this.cartService,
    this.onCorrectionSubmitted,
    this.onRetryTeaching,
    this.isSameSenderAsPrevious = false,
    this.formatTime,
  }) : super(key: key);

  final ChatMessage message;
  final int messageIndex;
  final bool isDark;
  final AiCartService? cartService;
  final void Function(String correction)? onCorrectionSubmitted;
  final void Function(int index)? onRetryTeaching;
  final bool isSameSenderAsPrevious;
  final String Function(DateTime)? formatTime;

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final showAvatar = !widget.isSameSenderAsPrevious;
    return Container(
      margin: EdgeInsets.only(
        top: 2,
        bottom: widget.isSameSenderAsPrevious ? 2 : 8,
      ),
      child: Row(
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser && showAvatar)
            CircleAvatar(
              child: Icon(Icons.restaurant, color: Colors.white, size: 20),
              backgroundColor: Color(COLOR_PRIMARY),
              radius: 16,
            )
          else if (!message.isUser && !showAvatar)
            const SizedBox(width: 32),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.85,
              ),
              margin: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: message.isUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  message.isUser
                      ? _buildUserBubble(context)
                      : _buildAssistantBubble(context),
                  if (widget.formatTime != null &&
                      message.timestamp != null) ...[
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        widget.formatTime!(message.timestamp!),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[500],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (message.isUser && showAvatar)
            CircleAvatar(
              child: Icon(Icons.person, color: Colors.white, size: 20),
              backgroundColor: Colors.blue[700],
              radius: 16,
            )
          else if (message.isUser && !showAvatar)
            const SizedBox(width: 32),
        ],
      ),
    );
  }

  Widget _buildUserBubble(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(COLOR_PRIMARY).withValues(alpha: 0.9),
            Color(COLOR_PRIMARY),
          ],
        ),
        borderRadius: BorderRadius.circular(18).copyWith(
          bottomRight: const Radius.circular(4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            offset: const Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Text(
        widget.message.text,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        maxLines: 50,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildAssistantBubble(BuildContext context) {
    Widget child;
    switch (widget.message.type) {
      case MessageType.restaurantList:
        child = RestaurantListCard(data: widget.message.data ?? {});
        break;
      case MessageType.productList:
        child = ProductListCard(
          data: widget.message.data ?? {},
          cartService: widget.cartService ?? AiCartService(
            cartDatabase: Provider.of<CartDatabase>(context, listen: false),
          ),
        );
        break;
      case MessageType.orderStatus:
        child = OrderStatusCard(data: widget.message.data ?? {});
        break;
      case MessageType.orderList:
        child = OrderListCard(data: widget.message.data ?? {});
        break;
      case MessageType.bookingConfirmation:
        child = BookingConfirmationCard(data: widget.message.data ?? {});
        break;
      case MessageType.popularList:
        child = PopularListCard(
          data: widget.message.data ?? {},
          cartService: widget.cartService ?? AiCartService(
            cartDatabase: Provider.of<CartDatabase>(context, listen: false),
          ),
        );
        break;
      case MessageType.couponResult:
        child = CouponResultCard(data: widget.message.data ?? {});
        break;
      case MessageType.closedRestaurant:
        final data = widget.message.data as Map<String, dynamic>? ?? {};
        child = ClosedRestaurantCard(data: data);
        break;
      default:
        child = Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.isDark ? Colors.grey[700] : Colors.white,
            borderRadius: BorderRadius.circular(18).copyWith(
              bottomLeft: const Radius.circular(4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                offset: const Offset(0, 2),
                blurRadius: 4,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.message.text,
                style: TextStyle(
                  color: widget.isDark ? Colors.white : Colors.black87,
                  fontSize: 15,
                ),
                maxLines: 50,
                overflow: TextOverflow.ellipsis,
              ),
              if (widget.message.teachingStatus != null) ...[
                const SizedBox(height: 8),
                _buildTeachingStatusRow(),
              ],
            ],
          ),
        );
    }
    return child;
  }

  Widget _buildTeachingStatusRow() {
    final status = widget.message.teachingStatus!;
    switch (status) {
      case TeachingStatus.pending:
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              Color(COLOR_PRIMARY),
            ),
          ),
        );
      case TeachingStatus.saved:
        return Icon(
          Icons.check_circle,
          color: Colors.green,
          size: 16,
        );
      case TeachingStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: 'Failed to save – check connection',
              child: Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 16,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: widget.messageIndex >= 0 &&
                      widget.onRetryTeaching != null
                  ? () => widget.onRetryTeaching!(widget.messageIndex)
                  : null,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Retry', style: TextStyle(fontSize: 12)),
            ),
          ],
        );
    }
  }
}
