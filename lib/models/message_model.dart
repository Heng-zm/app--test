import 'package:hive/hive.dart';

part 'message_model.g.dart';

@HiveType(typeId: 0)
class Message extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String text;

  @HiveField(2)
  final String encryptedText;

  @HiveField(3)
  final bool isMine;

  @HiveField(4)
  final DateTime timestamp;

  @HiveField(5)
  final bool isDecryptionError;

  Message({
    required this.id,
    required this.text,
    required this.encryptedText,
    required this.isMine,
    required this.timestamp,
    this.isDecryptionError = false,
  });

  /// Returns true if the message was successfully decrypted
  bool get isValid => !isDecryptionError;

  String get timeString {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String get dateString {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(timestamp.year, timestamp.month, timestamp.day);

    final difference = today.difference(msgDate).inDays;

    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';

    // Format: DD/MM/YYYY
    return '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')}/${timestamp.year}';
  }

  Message copyWith({
    String? id,
    String? text,
    String? encryptedText,
    bool? isMine,
    DateTime? timestamp,
    bool? isDecryptionError,
  }) {
    return Message(
      id: id ?? this.id,
      text: text ?? this.text,
      encryptedText: encryptedText ?? this.encryptedText,
      isMine: isMine ?? this.isMine,
      timestamp: timestamp ?? this.timestamp,
      isDecryptionError: isDecryptionError ?? this.isDecryptionError,
    );
  }
}
