import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// AES-256-CBC with a random IV per message (prepended to the ciphertext).
///
/// Format v2: base64( 16-byte-IV + ciphertext )
/// Format v1 (Legacy): base64( ciphertext ) with IV derived from MD5(key)
class EncryptionService {
  static const String _defaultPassphrase = 'BT_CHAT_SECURE_KEY_2024';

  late enc.Key _key;
  late enc.Encrypter _encrypter;
  late enc.IV
      _legacyIv; // 🛠️ FIX: Cached to avoid recalculating MD5 per message

  EncryptionService({String? passphrase}) {
    _initKey(passphrase ?? _defaultPassphrase);
  }

  /// Derives a 32-byte key using SHA-256 and initializes the AES engine.
  void _initKey(String passphrase) {
    final keyBytes = sha256.convert(utf8.encode(passphrase)).bytes;
    _key = enc.Key(Uint8List.fromList(keyBytes));
    _encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.cbc));

    // 🛠️ PERF: Pre-calculate the legacy IV once when the key changes.
    // Previously, md5.convert(...) ran on every single legacy message received.
    final ivBytes = md5.convert(utf8.encode(passphrase)).bytes;
    _legacyIv = enc.IV(Uint8List.fromList(ivBytes));
  }

  /// Encrypts text and prepends a random 16-byte IV.
  /// Format: base64(IV + Ciphertext)
  String encrypt(String plaintext) {
    try {
      final iv = enc.IV.fromSecureRandom(16);
      final encrypted = _encrypter.encrypt(plaintext, iv: iv);

      final combined = Uint8List(16 + encrypted.bytes.length)
        ..setRange(0, 16, iv.bytes)
        ..setRange(16, 16 + encrypted.bytes.length, encrypted.bytes);

      return base64.encode(combined);
    } catch (e) {
      throw EncryptionException('Encryption engine failure: $e');
    }
  }

  /// Decrypts payload. Tries v2 (Random IV) first, then falls back to v1 (Legacy).
  String decrypt(String payload) {
    Uint8List combined;

    try {
      // 🛠️ FIX: Decode base64 exactly once. If it fails here, it's corrupted
      // data over Bluetooth, and we shouldn't attempt legacy decryption at all.
      combined = base64.decode(payload);
    } catch (e) {
      throw const EncryptionException(
          'Decryption Failed: Invalid Base64 payload.');
    }

    // 🛠️ PERF/FIX: AES-CBC ciphertexts are always multiples of 16.
    // V2 is 16 (IV) + multiple of 16 = min 32 bytes and % 16 == 0.
    // This strict check avoids throwing/catching expensive PaddingExceptions
    // when processing short legacy payloads.
    if (combined.length >= 32 && combined.length % 16 == 0) {
      try {
        // 🛠️ PERF: Use `Uint8List.sublistView` instead of `.sublist`.
        // `.sublist` creates brand new memory copies. `sublistView` creates a
        // zero-copy pointer window into existing memory, saving CPU/GC overhead.
        final iv = enc.IV(Uint8List.sublistView(combined, 0, 16));
        final cipher = enc.Encrypted(Uint8List.sublistView(combined, 16));
        return _encrypter.decrypt(cipher, iv: iv);
      } catch (_) {
        // Fall through to legacy if V2 decryption fails (wrong padding/key)
      }
    }

    return _decryptLegacyBytes(combined);
  }

  /// v1 static-IV fallback for older versions of the app.
  String _decryptLegacyBytes(Uint8List cipherBytes) {
    try {
      // 🛠️ PERF: Use pre-decoded bytes and cached IV.
      // Previously this called `Encrypted.fromBase64` which re-ran the Base64 decoder.
      final encrypted = enc.Encrypted(cipherBytes);
      return _encrypter.decrypt(encrypted, iv: _legacyIv);
    } catch (e) {
      throw const EncryptionException(
          'Decryption Failed: Data corruption or invalid key.');
    }
  }

  /// Updates the internal key state when the user changes settings.
  void updatePassphrase(String newPassphrase) => _initKey(newPassphrase);

  /// Generates a cryptographically secure random 24-character passphrase.
  static String generatePassphrase() {
    final bytes = enc.SecureRandom(18).bytes;
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Creates a visual 8-digit fingerprint for manual key verification.
  static String hashPreview(String passphrase) {
    if (passphrase.isEmpty) return '00000000';
    return sha256
        .convert(utf8.encode(passphrase))
        .toString()
        .substring(0, 8)
        .toUpperCase();
  }
}

/// Specialized exception for encryption errors.
class EncryptionException implements Exception {
  final String message;
  const EncryptionException(this.message);

  @override
  String toString() => message;
}
