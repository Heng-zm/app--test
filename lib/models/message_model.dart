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

  /// Returns true if the message was successfully decrypted and is readable.
  bool get isValid => !isDecryptionError;

  /// Returns a formatted time string (e.g., "14:30").
  String get timeString {
    final String h = timestamp.hour.toString().padLeft(2, '0');
    final String m = timestamp.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Returns a human-friendly date string (Today, Yesterday, or DD/MM/YYYY).
  String get dateString {
    final DateTime now = DateTime.now();

    // Normalize dates to midnight to compare calendar days accurately.
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime yesterday = today.subtract(const Duration(days: 1));
    final DateTime msgDate =
        DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (msgDate == today) {
      return 'Today';
    }

    if (msgDate == yesterday) {
      return 'Yesterday';
    }

    // Format: DD/MM/YYYY
    final String d = timestamp.day.toString().padLeft(2, '0');
    final String m = timestamp.month.toString().padLeft(2, '0');
    final String y = timestamp.year.toString();

    return '$d/$m/$y';
  }

  /// Creates a copy of this message with changed fields.
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
