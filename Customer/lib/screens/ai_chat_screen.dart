import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/services/ai_cart_service.dart';
import 'package:foodie_customer/services/word_correction_service.dart';
import 'package:foodie_customer/services/ai_tool_declarations.dart';
import 'package:foodie_customer/services/ai_chat_tool_handler.dart';
import 'package:foodie_customer/services/localDatabase.dart';
import 'package:foodie_customer/screens/ai_chat_cards.dart';

class AiChatScreen extends StatefulWidget {
  @override
  _AiChatScreenState createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _greetingAdded = false;

  late ChatSession _chat;
  late AiChatToolHandler _toolHandler;
  late AiCartService _aiCartService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_greetingAdded && mounted) {
        setState(() {
          _messages.add(ChatMessage(
            type: MessageType.text,
            text: "Hi! I'm your Lalago assistant. How can I help you today?",
            isUser: false,
          ));
          _greetingAdded = true;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_chatInitialized) {
      _chatInitialized = true;
      _initChat();
    }
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
    return '''
You are a helpful food assistant for the Lalago app, serving users in the
Philippines including Tausug-speaking communities in Sulu.

LANGUAGE GUIDELINES:
- If the user asks in English, respond in English.
- If the user asks in Tagalog/Filipino, respond in Tagalog.
- If the user asks in Tausug (or mixes Tausug with other languages), try to
  understand their request and respond in a mix of Tagalog and English to
  ensure clarity, since Tausug is not officially supported.
- Common Tausug food terms: pastil (wrapped rice), pyanggang (grilled chicken),
  satti (satay), tiyula (soup), juring/lumpia (spring rolls), putli (dessert),
  durul (snack).

TASKS: Use tools whenever possible.
- search_restaurants for restaurant recommendations
- search_products for food/products (use English equivalents for Tausug terms)
- get_popular_items for "popular today"
- get_order_status or get_active_orders for order tracking
- add_products_to_cart to add items; user completes checkout in the app
- apply_best_coupon for best offers
- Confirm table bookings before finalizing
- If user is not signed in, tell them to sign in for actions that require it.
''';
  }

  void _initChat() {
    final cartDatabase = Provider.of<CartDatabase>(context, listen: false);
    _aiCartService = AiCartService(cartDatabase: cartDatabase);
    _toolHandler = AiChatToolHandler(
      userId: MyAppState.currentUser?.userID,
      aiCartService: _aiCartService,
      cartDatabase: cartDatabase,
      context: context,
    );

    final systemPrompt = _buildSystemPrompt();

    final model = FirebaseAI.googleAI().generativeModel(
      model: 'gemini-2.5-flash-lite',
      tools: [Tool.functionDeclarations(aiToolDeclarations)],
      systemInstruction: Content.system(systemPrompt),
    );
    _chat = model.startChat();
  }

  void _sendMessage() async {
    if (_controller.text.trim().isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(
        type: MessageType.text,
        text: _controller.text,
        isUser: true,
      ));
      _isLoading = true;
    });

    final userQuery = _controller.text;
    _controller.clear();

    try {
      final correctionHint =
          await WordCorrectionService.getCorrectionHintForQuery(userQuery);
      final content = correctionHint.isNotEmpty
          ? Content.text('$correctionHint\n\nUser question: $userQuery')
          : Content.text(userQuery);
      var response = await _chat.sendMessage(content);
      String? lastToolName;
      Map<String, dynamic>? lastResult;

      while (response.functionCalls.isNotEmpty) {
        final functionCalls = response.functionCalls.toList();
        for (final fc in functionCalls) {
          Map<String, dynamic> result;
          if (fc.name == 'book_table') {
            final details = await _toolHandler.executeTool(
              'book_table',
              _toDynamicMap(fc.args),
            );
            if (details['pendingConfirmation'] == true && mounted) {
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
          lastToolName = fc.name;
          lastResult = result;
          response = await _chat.sendMessage(
            Content.functionResponse(fc.name, result),
          );
        }
      }

      if (mounted) {
        setState(() {
          final richType = _messageTypeForTool(lastToolName, lastResult);
          if (richType != null && lastResult != null) {
            final msg = (lastResult['message'] ?? '').toString();
            _messages.add(ChatMessage(
              type: richType,
              text: msg,
              data: lastResult,
              isUser: false,
            ));
          }
          final text = response.text?.trim() ?? '';
          if (text.isNotEmpty) {
            _messages.add(ChatMessage(
              type: MessageType.text,
              text: text,
              isUser: false,
            ));
          } else if (richType == null) {
            _messages.add(ChatMessage(
              type: MessageType.text,
              text: "Sorry, I couldn't complete that.",
              isUser: false,
            ));
          }
        });
      }
    } catch (e) {
      debugPrint('ERROR in _sendMessage: $e');
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            type: MessageType.text,
            text: 'Error: $e',
            isUser: false,
          ));
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Map<String, dynamic> _toDynamicMap(Map<String, Object?> args) {
    return Map<String, dynamic>.from(args);
  }

  MessageType? _messageTypeForTool(
    String? toolName,
    Map<String, dynamic>? result,
  ) {
    if (toolName == null || result == null) return null;
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

    try {
      await WordCorrectionService.store(
        userId: userId,
        userQuery: userMessage.text,
        aiResponse: aiMessage.text,
        correction: correctionText,
        detectedWords: _detectTausugWords(userMessage.text),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thank you for teaching me!')),
        );
      }
    } catch (e) {
      debugPrint('Error storing word correction: $e');
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
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask Lalago'),
        backgroundColor: Color(COLOR_PRIMARY),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return ChatBubble(
                  message: _messages[index],
                  isDark: isDark,
                  cartService: _aiCartService,
                  onCorrectionSubmitted: (correction) =>
                      _saveWordCorrection(_messages[index], correction),
                );
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'What are you craving?',
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                  color: Color(COLOR_PRIMARY),
                ),
              ],
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
}

class ChatMessage {
  final MessageType type;
  final String text;
  final dynamic data;
  final bool isUser;

  ChatMessage({
    required this.type,
    required this.text,
    this.data,
    required this.isUser,
  });
}

class ChatBubble extends StatefulWidget {
  const ChatBubble({
    Key? key,
    required this.message,
    this.isDark = false,
    this.cartService,
    this.onCorrectionSubmitted,
  }) : super(key: key);

  final ChatMessage message;
  final bool isDark;
  final AiCartService? cartService;
  final void Function(String correction)? onCorrectionSubmitted;

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  bool _showCorrectionField = false;
  final TextEditingController _correctionController = TextEditingController();

  @override
  void dispose() {
    _correctionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser)
            CircleAvatar(
              child: Icon(Icons.restaurant, color: Colors.white, size: 20),
              backgroundColor: Color(COLOR_PRIMARY),
              radius: 16,
            ),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.85,
              ),
              margin: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  message.isUser
                      ? _buildUserBubble(context)
                      : _buildAssistantBubble(context),
                  if (!message.isUser &&
                      widget.onCorrectionSubmitted != null)
                    _buildFeedbackRow(context),
                ],
              ),
            ),
          ),
          if (message.isUser)
            CircleAvatar(
              child: Icon(Icons.person, color: Colors.white, size: 20),
              backgroundColor: Colors.blue[700],
              radius: 16,
            ),
        ],
      ),
    );
  }

  Widget _buildFeedbackRow(BuildContext context) {
    if (_showCorrectionField) {
      return Padding(
        padding: const EdgeInsets.only(left: 8, top: 8, right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Which word was misunderstood? What should it mean?',
              style: TextStyle(
                fontSize: 13,
                color: widget.isDark ? Colors.grey[300] : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _correctionController,
                    decoration: InputDecoration(
                      hintText: 'e.g., "hawnu" means "where"',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.all(8),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    final text = _correctionController.text.trim();
                    if (text.isNotEmpty) {
                      widget.onCorrectionSubmitted?.call(text);
                      _correctionController.clear();
                      setState(() => _showCorrectionField = false);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.translate, size: 18),
          onPressed: () => setState(() => _showCorrectionField = true),
          tooltip: 'Suggest word correction',
        ),
      ],
    );
  }

  Widget _buildUserBubble(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color(COLOR_PRIMARY),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        widget.message.text,
        style: const TextStyle(color: Colors.white, fontSize: 15),
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
        child = PopularListCard(data: widget.message.data ?? {});
        break;
      case MessageType.couponResult:
        child = CouponResultCard(data: widget.message.data ?? {});
        break;
      default:
        child = Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.isDark ? Colors.grey[700] : Colors.grey[300],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            widget.message.text,
            style: const TextStyle(color: Colors.black87, fontSize: 15),
          ),
        );
    }
    return child;
  }
}
