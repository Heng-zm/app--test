import 'dart:convert';
import 'dart:typed_data';
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

  @HiveField(6)
  final bool isImage;

  // ── New fields (HiveFields 7-9) ──────────────────────────────────────────
  @HiveField(7)
  final bool isDocument;

  @HiveField(8)
  final String? caption;

  @HiveField(9)
  final String? fileName;

  @HiveField(10)
  final int? fileSizeBytes;

  Message({
    required this.id,
    required this.text,
    required this.encryptedText,
    required this.isMine,
    required this.timestamp,
    this.isDecryptionError = false,
    this.isImage = false,
    this.isDocument = false,
    this.caption,
    this.fileName,
    this.fileSizeBytes,
  });

  // ── Derived / cached properties ─────────────────────────────────────────

  Uint8List? _cachedBytes;
  Uint8List? get imageBytes {
    if (!isImage || text.isEmpty) return null;
    if (_cachedBytes != null) return _cachedBytes;
    try {
      return _cachedBytes = base64Decode(text);
    } catch (_) {
      return null;
    }
  }

  /// Human-readable file size label for document bubbles.
  // 🟢 PERF: `late final` — computed once on first access.
  late final String? fileSizeLabel = () {
    final n = fileSizeBytes;
    if (n == null) return null;
    if (n < 1024) return '${n}B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)}KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)}MB';
  }();

  late final String timeString = () {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }();

  late final String dateString = () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (msgDay == today) return 'Today';
    if (msgDay == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return _formatDate(timestamp, includeYear: timestamp.year != now.year);
  }();

  static String _formatDate(DateTime dt, {bool includeYear = false}) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return includeYear ? '$d/$m/${dt.year}' : '$d/$m';
  }

  String get previewText {
    if (isImage) return '[SECURE IMAGE DATA]';
    // 🟢 FIX: Cover new document type in preview.
    if (isDocument) return '[SECURE FILE: ${fileName ?? 'document'}]';
    if (isDecryptionError) return '[DECRYPTION FAILURE]';
    if (text.length <= 50) return text;
    final runes = text.runes.toList();
    if (runes.length <= 50) return text;
    return '${String.fromCharCodes(runes.take(50))}...';
  }

  bool get isHeavy => isImage && text.length > 20000;

  // ── Equality & hashing ───────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Message &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          text == other.text &&
          isImage == other.isImage &&
          // 🟢 FIX: Include new fields in equality check.
          isDocument == other.isDocument &&
          isDecryptionError == other.isDecryptionError &&
          timestamp.millisecondsSinceEpoch ==
              other.timestamp.millisecondsSinceEpoch;

  @override
  int get hashCode => Object.hash(
        id,
        text,
        isImage,
        isDocument,
        isDecryptionError,
        timestamp.millisecondsSinceEpoch,
      );

  // ── Mutation helpers ─────────────────────────────────────────────────────

  Message copyWith({
    String? id,
    String? text,
    String? encryptedText,
    bool? isMine,
    DateTime? timestamp,
    bool? isDecryptionError,
    bool? isImage,
    bool? isDocument,
    String? caption,
    String? fileName,
    int? fileSizeBytes,
  }) {
    return Message(
      id: id ?? this.id,
      text: text ?? this.text,
      encryptedText: encryptedText ?? this.encryptedText,
      isMine: isMine ?? this.isMine,
      timestamp: timestamp ?? this.timestamp,
      isDecryptionError: isDecryptionError ?? this.isDecryptionError,
      isImage: isImage ?? this.isImage,
      isDocument: isDocument ?? this.isDocument,
      caption: caption ?? this.caption,
      fileName: fileName ?? this.fileName,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
    );
  }
}
