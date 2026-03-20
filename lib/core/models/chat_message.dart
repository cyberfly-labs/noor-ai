class ChatMessage {
  final String id;
  final String content;
  final String role; // 'user' | 'assistant'
  final String? intent;
  final String? verseKey;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.content,
    required this.role,
    this.intent,
    this.verseKey,
    required this.createdAt,
  });

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  factory ChatMessage.fromDb(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as String,
      content: map['content'] as String,
      role: map['role'] as String,
      intent: map['intent'] as String?,
      verseKey: map['verse_key'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  Map<String, dynamic> toDb() => {
    'id': id,
    'content': content,
    'role': role,
    'intent': intent,
    'verse_key': verseKey,
    'created_at': createdAt.millisecondsSinceEpoch,
  };
}
