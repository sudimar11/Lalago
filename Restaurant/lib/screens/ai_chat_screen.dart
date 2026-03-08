import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/main.dart';
import 'package:foodie_restaurant/services/ai_tool_declarations.dart';
import 'package:foodie_restaurant/services/ai_chat_tool_handler.dart';
import 'package:foodie_restaurant/services/helper.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({Key? key}) : super(key: key);

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<_ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _greetingAdded = false;
  bool _disposed = false;
  Timer? _loadingTimer;
  int _currentMessageIndex = 0;
  static const _loadingMessages = [
    'Checking demand forecasts...',
    'Looking up driver performance...',
    'Ash is thinking...',
  ];

  late ChatSession _chat;
  late AiChatToolHandler _toolHandler;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_greetingAdded && mounted) {
        setState(() {
          _messages.add(_ChatMessage(
            text: _getIntro(),
            isUser: false,
            timestamp: DateTime.now(),
          ));
          _greetingAdded = true;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initChatIfNeeded();
  }

  bool _chatInitialized = false;

  void _initChatIfNeeded() {
    if (_chatInitialized) return;
    final vendorId = MyAppState.currentUser?.vendorID;
    if (vendorId == null || vendorId.isEmpty) return;

    _chatInitialized = true;
    _toolHandler = AiChatToolHandler(vendorId: vendorId);
    final systemPrompt = '''
You are Ash, a helpful operations assistant for restaurant staff in the Lalago app.
You can help with:
- Demand forecasts and inventory planning
- Driver performance and incentives
- Sales insights and popular items
- Restaurant status and hours
- Reorder suggestions based on forecasts

Answer concisely. Use tool results to give specific, actionable answers.
Identify yourself as Ash when appropriate.
''';
    final model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: GOOGLE_API_KEY,
      systemInstruction: Content.system(systemPrompt),
      tools: [
        Tool(functionDeclarations: restaurantAiToolDeclarations),
      ],
    );
    _chat = model.startChat();
  }

  String _getIntro() {
    final hour = DateTime.now().hour;
    String greeting = 'Hi there!';
    if (hour >= 5 && hour < 12) greeting = 'Good morning!';
    else if (hour >= 12 && hour < 18) greeting = 'Good afternoon!';
    else if (hour >= 18 && hour < 22) greeting = 'Good evening!';
    return '$greeting I\'m Ash, your operations assistant. '
        'I can help with forecasts, drivers, sales, and more. How can I help?';
  }

  void _sendMessage() async {
    if (_controller.text.trim().isEmpty) return;

    final userQuery = _controller.text.trim();
    setState(() {
      _messages.add(_ChatMessage(
        text: userQuery,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isLoading = true;
      _currentMessageIndex = 0;
    });
    _controller.clear();

    _loadingTimer?.cancel();
    _loadingTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) {
        if (!_isLoading || _disposed || !mounted) return;
        setState(() {
          _currentMessageIndex =
              (_currentMessageIndex + 1) % _loadingMessages.length;
        });
      },
    );

    try {
      final content = Content.text(userQuery);
      var response = await _chat.sendMessage(content);
      Map<String, dynamic>? lastResult;
      int loopCount = 0;

      while (response.functionCalls.isNotEmpty && loopCount < 10) {
        loopCount++;
        for (final fc in response.functionCalls) {
          final result = await _toolHandler.executeTool(
            fc.name,
            Map<String, dynamic>.from(fc.args),
          );
          lastResult = result;
          response = await _chat.sendMessage(
            Content.functionResponse(fc.name, result),
          );
        }
      }

      String text = response.text?.trim() ?? '';
      if (text.isEmpty && lastResult != null) {
        text = (lastResult['message'] ?? lastResult['error'] ?? 'Done.')
            .toString();
      }
      if (text.isEmpty) text = 'Sorry, I couldn\'t complete that.';

      if (!_disposed && mounted) {
        setState(() {
          _messages.add(_ChatMessage(
            text: text,
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
      }
    } catch (e) {
      final msg = e.toString().toLowerCase().contains('network') ||
              e.toString().toLowerCase().contains('socket')
          ? 'No internet. Check your connection and try again.'
          : 'Something went wrong. Please try again.';
      if (!_disposed && mounted) {
        setState(() {
          _messages.add(_ChatMessage(
            text: msg,
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
      }
    } finally {
      _loadingTimer?.cancel();
      _loadingTimer = null;
      if (!_disposed && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _loadingTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkMode(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.assistant, color: Colors.white),
            SizedBox(width: 8),
            Text('Ask Ash'),
          ],
        ),
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
                final msg = _messages[index];
                return _ChatBubble(
                  message: msg,
                  isDark: isDark,
                );
              },
            ),
          ),
          if (_isLoading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _loadingMessages[
                        _currentMessageIndex % _loadingMessages.length],
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
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
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: 'Ask about forecasts, drivers, sales...',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(16),
                          filled: true,
                          fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                        ),
                        maxLines: null,
                        enabled: !_isLoading,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    if (_isLoading)
                      const SizedBox(width: 48)
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

class _ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  _ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.isDark,
  });

  final _ChatMessage message;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser)
            CircleAvatar(
              radius: 16,
              backgroundColor: Color(COLOR_PRIMARY),
              child: Icon(Icons.restaurant, color: Colors.white, size: 20),
            ),
          if (!message.isUser) const SizedBox(width: 8),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.85,
              ),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: message.isUser
                    ? Color(COLOR_PRIMARY)
                    : (isDark ? Colors.grey[700] : Colors.grey[200]),
                borderRadius: BorderRadius.circular(18).copyWith(
                  bottomRight: message.isUser
                      ? const Radius.circular(4)
                      : const Radius.circular(18),
                  bottomLeft: message.isUser
                      ? const Radius.circular(18)
                      : const Radius.circular(4),
                ),
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  color: message.isUser
                      ? Colors.white
                      : (isDark ? Colors.white : Colors.black87),
                  fontSize: 15,
                ),
                maxLines: 50,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (message.isUser) const SizedBox(width: 8),
          if (message.isUser)
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue[700],
              child: Icon(Icons.person, color: Colors.white, size: 20),
            ),
        ],
      ),
    );
  }
}
