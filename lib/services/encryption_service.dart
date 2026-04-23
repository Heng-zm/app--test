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
  String _passphrase = _defaultPassphrase;

  EncryptionService({String? passphrase}) {
    _initKey(passphrase ?? _defaultPassphrase);
  }

  /// Derives a 32-byte key using SHA-256 and initializes the AES engine.
  void _initKey(String passphrase) {
    _passphrase = passphrase;
    // Derive 256-bit key from variable length passphrase
    final keyBytes = sha256.convert(utf8.encode(passphrase)).bytes;
    _key = enc.Key(Uint8List.fromList(keyBytes));

    // We use CBC mode with PKCS7 padding
    _encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.cbc));
  }

  /// Encrypts text and prepends a random 16-byte IV.
  /// Format: base64(IV + Ciphertext)
  String encrypt(String plaintext) {
    try {
      final iv = enc.IV.fromSecureRandom(16);
      final encrypted = _encrypter.encrypt(plaintext, iv: iv);

      // Create a combined buffer: [IV (16 bytes)][Encrypted Bytes]
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
    try {
      final combined = base64.decode(payload);

      // Check if it's potentially a v2 message (at least 16 bytes for IV + data)
      if (combined.length >= 17) {
        final iv = enc.IV(Uint8List.fromList(combined.sublist(0, 16)));
        final cipher = enc.Encrypted(Uint8List.fromList(combined.sublist(16)));
        return _encrypter.decrypt(cipher, iv: iv);
      }
    } catch (_) {
      // If combined decoding fails, treat as potential legacy v1 string
    }

    return _decryptLegacy(payload);
  }

  /// v1 static-IV fallback for older versions of the app.
  String _decryptLegacy(String ciphertext) {
    try {
      // Legacy used MD5 of passphrase as the static IV
      final ivBytes = md5.convert(utf8.encode(_passphrase)).bytes;
      final iv = enc.IV(Uint8List.fromList(ivBytes));
      final encrypted = enc.Encrypted.fromBase64(ciphertext);
      return _encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      throw const EncryptionException(
          'Decryption Failed: Data corruption or invalid key.');
    }
  }

  /// Updates the internal key state when the user changes settings.
  void updatePassphrase(String newPassphrase) => _initKey(newPassphrase);

  /// Generates a cryptographically secure random 24-character passphrase.
  static String generatePassphrase() {
    final bytes = enc.SecureRandom(18).bytes; // 18 bytes -> 24 base64 chars
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Creates a visual 8-digit fingerprint for manual key verification.
  static String hashPreview(String passphrase) {
    if (passphrase.isEmpty) {
      return '00000000';
    }
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

  // FIXED: Constructor is now const to resolve analyzer info
  const EncryptionException(this.message);

  @override
  String toString() => message;
}
