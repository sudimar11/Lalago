import 'package:firebase_ai/firebase_ai.dart';

Future<String?> testGemini() async {
  final model = FirebaseAI.googleAI().generativeModel(
    model: 'gemini-2.5-flash-lite',
  );
  final response = await model.generateContent([
    Content.text('Hello, what can you recommend for dinner?'),
  ]);
  return response.text;
}
