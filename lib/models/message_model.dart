import 'package:hive/hive.dart';

part 'message_model.g.dart';

@HiveType(typeId: 0)
class Message extends HiveObject {
  @HiveField(0)
  final String id;

  /// Stores the decrypted text OR the Base64 string for images.
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

  @HiveField(6)
  final bool isImage;

  Message({
    required this.id,
    required this.text,
    required this.encryptedText,
    required this.isMine,
    required this.timestamp,
    this.isDecryptionError = false,
    this.isImage = false,
  });

  // 🟢 PERF: Pre-calculated and cached to prevent expensive padding
  // operations during ListView scrolling.
  late final String timeString = () {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }();

  /// 🟢 PERF: Returns a safe, short preview.
  /// Prevents UI jank when displaying logs that contain large Base64 image data.
  String get previewText {
    if (isImage) return '[SECURE IMAGE DATA]';
    if (isDecryptionError) return '[DECRYPTION FAILURE]';
    return text.length > 50 ? '${text.substring(0, 50)}...' : text;
  }

  /// DST-safe date label: 'Today', 'Yesterday', or DD/MM/YYYY.
  String get dateString {
    final now = DateTime.now();

    // Fast path: Check year first
    if (timestamp.year != now.year) {
      return _formatDate(timestamp);
    }

    if (timestamp.month == now.month && timestamp.day == now.day) {
      return 'Today';
    }

    // DST-safe yesterday logic
    final yesterdayDate = DateTime(now.year, now.month, now.day - 1);
    if (timestamp.month == yesterdayDate.month &&
        timestamp.day == yesterdayDate.day) {
      return 'Yesterday';
    }

    return _formatDate(timestamp);
  }

  static String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d/$m/${dt.year}';
  }

  /// Threshold for GPU-heavy image caching
  bool get isHeavy => isImage && text.length > 4096;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Message &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          isImage == other.isImage && // 🟢 FIX: Include type in equality
          isDecryptionError == other.isDecryptionError;

  @override
  int get hashCode => Object.hash(id, isImage, isDecryptionError);

  Message copyWith({
    String? id,
    String? text,
    String? encryptedText,
    bool? isMine,
    DateTime? timestamp,
    bool? isDecryptionError,
    bool? isImage,
  }) {
    return Message(
      id: id ?? this.id,
      text: text ?? this.text,
      encryptedText: encryptedText ?? this.encryptedText,
      isMine: isMine ?? this.isMine,
      timestamp: timestamp ?? this.timestamp,
      isDecryptionError: isDecryptionError ?? this.isDecryptionError,
      isImage: isImage ?? this.isImage,
    );
  }
}
