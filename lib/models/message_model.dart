import 'package:hive/hive.dart';

part 'message_model.g.dart';

// FIX: Removed @immutable annotation. HiveObject exposes mutable fields
// (`key`, `box`, `isInBox`) — annotating a subclass as @immutable is
// semantically incorrect and will produce analyzer warnings in strict mode.
// Immutability is enforced at the field level via `final` instead.
@HiveType(typeId: 0)
class Message extends HiveObject {
  @HiveField(0)
  final String id;

  /// Stores the decrypted text or the Base64 string for images.
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

  // PERF: Cached via late final to avoid repeated padLeft allocations on
  // every widget rebuild. Safe because timestamp is final and never changes.
  late final String timeString = '${timestamp.hour.toString().padLeft(2, '0')}:'
      '${timestamp.minute.toString().padLeft(2, '0')}';

  /// Returns a human-readable date label: 'Today', 'Yesterday', or DD/MM/YYYY.
  ///
  /// FIX: The original used `now.subtract(Duration(days: 1))` to get
  /// "yesterday", which is incorrect at DST transitions — subtracting 23 or
  /// 25 hours can land on the wrong calendar date. We now use explicit
  /// date-component arithmetic instead, which is DST-safe.
  ///
  /// PERF: Year is checked first as the fastest short-circuit — messages from
  /// a different year skip the day/month comparisons entirely.
  String get dateString {
    final now = DateTime.now();

    // Fast path: different year — skip all other checks
    if (timestamp.year != now.year) {
      return _formatDate(timestamp);
    }

    if (timestamp.month == now.month && timestamp.day == now.day) {
      return 'Today';
    }

    // DST-safe yesterday: decrement the calendar date, not a Duration.
    final yesterdayDate = DateTime(now.year, now.month, now.day - 1);
    if (timestamp.year == yesterdayDate.year &&
        timestamp.month == yesterdayDate.month &&
        timestamp.day == yesterdayDate.day) {
      return 'Yesterday';
    }

    return _formatDate(timestamp);
  }

  // PERF: Extracted helper — avoids repeating the padLeft calls in two
  // branches and keeps dateString readable.
  static String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';

  /// Returns true when the payload is large enough to warrant GPU-side
  /// rendering decisions (e.g. caching decoded image data).
  ///
  /// FIX: Threshold raised from 1024 → 4096. A Base64-encoded image is
  /// ~1.37× its binary size; even a 32×32 PNG easily exceeds 1 KB of Base64.
  /// 1024 was producing false positives for small thumbnails. 4096 (~3 KB
  /// binary) is a more realistic lower bound for "heavy" image content.
  bool get isHeavy => isImage && text.length > 4096;

  /// Optimized equality: 'id' uniquely identifies a message; comparing the
  /// full 'text' field (potentially megabytes of Base64) on the UI thread
  /// causes jank. 'isDecryptionError' is included because the same id can
  /// transition from error → success after a retry, and the UI must reflect that.
  ///
  /// PERF: Object.hash() uses a better mixing function than manual XOR and
  /// reduces hash collisions in large message lists.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Message &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          isDecryptionError == other.isDecryptionError;

  @override
  int get hashCode => Object.hash(id, isDecryptionError);

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
