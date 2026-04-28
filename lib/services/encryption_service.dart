import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// AES-256-CBC Encryption Engine
///
/// Protocol v2 (Modern): [16-byte random IV] + [AES-256-CBC Ciphertext]
/// Protocol v1 (Legacy): [AES-256-CBC Ciphertext] using static IV from MD5(key)
class EncryptionService {
  static const String _defaultPassphrase = 'BT_CHAT_SECURE_KEY_2024';

  late enc.Key _key;
  late enc.Encrypter _encrypter;
  late enc.IV _legacyIv;

  EncryptionService({String? passphrase}) {
    _initKey(passphrase ?? _defaultPassphrase);
  }

  /// Initializes cryptographic state. Key derived via SHA-256.
  void _initKey(String passphrase) {
    final keyBytes = sha256.convert(utf8.encode(passphrase)).bytes;
    _key = enc.Key(Uint8List.fromList(keyBytes));
    _encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.cbc));

    // 🟢 PERF: Legacy IV derived once and cached to avoid MD5 overhead during chat
    final ivBytes = md5.convert(utf8.encode(passphrase)).bytes;
    _legacyIv = enc.IV(Uint8List.fromList(ivBytes));
  }

  /// Encrypts plaintext using AES-256-CBC with a unique random IV.
  /// Result: base64(IV + Ciphertext)
  String encrypt(String plaintext) {
    try {
      if (plaintext.isEmpty) return '';

      final iv = enc.IV.fromSecureRandom(16);
      final encrypted = _encrypter.encrypt(plaintext, iv: iv);

      // 🟢 PERF: Use a single allocation for the combined payload
      final combined = Uint8List(16 + encrypted.bytes.length);
      combined.setRange(0, 16, iv.bytes);
      combined.setRange(16, combined.length, encrypted.bytes);

      return base64.encode(combined);
    } catch (e) {
      throw EncryptionException('Encryption system failure: $e');
    }
  }

  /// Decrypts a base64 payload.
  /// Automatically detects and handles Protocol v1 (Legacy) and v2 (Modern).
  String decrypt(String payload) {
    if (payload.isEmpty) return '';

    final Uint8List combined;
    try {
      combined = base64.decode(payload);
    } catch (_) {
      throw const EncryptionException('Decryption Failed: Invalid encoding.');
    }

    // 🟢 Protocol v2 Heuristic: 16 (IV) + 16 (Min 1 Block) = 32 bytes minimum.
    // Must also be a multiple of the AES block size (16).
    if (combined.length >= 32 && combined.length % 16 == 0) {
      try {
        // 🟢 PERF: sublistView provides a zero-copy window into the original byte array
        final iv = enc.IV(Uint8List.sublistView(combined, 0, 16));
        final cipher = enc.Encrypted(Uint8List.sublistView(combined, 16));
        return _encrypter.decrypt(cipher, iv: iv);
      } catch (_) {
        // If v2 structure is valid but decryption fails, attempt legacy fallback
      }
    }

    return _decryptLegacyBytes(combined);
  }

  /// Protocol v1 Fallback: Static IV Decryption
  String _decryptLegacyBytes(Uint8List cipherBytes) {
    try {
      if (cipherBytes.isEmpty || cipherBytes.length % 16 != 0) {
        throw const EncryptionException('Payload corruption');
      }
      return _encrypter.decrypt(enc.Encrypted(cipherBytes), iv: _legacyIv);
    } catch (e) {
      throw const EncryptionException(
          'Decryption Failed: Cipher/Key mismatch.');
    }
  }

  /// Live-swaps the encryption key (e.g., user changed passphrase in settings)
  void updatePassphrase(String newPassphrase) => _initKey(newPassphrase);

  /// Generates a high-entropy random passphrase
  static String generatePassphrase() {
    final bytes = enc.SecureRandom(24).bytes;
    return base64Url.encode(bytes).replaceAll('=', '').substring(0, 32);
  }

  /// Generates an 8-character visual fingerprint of the current key
  static String hashPreview(String passphrase) {
    if (passphrase.isEmpty) return '00000000';
    // 🟢 PERF: toString() on SHA-256 result is already hex-encoded
    final hash = sha256.convert(utf8.encode(passphrase)).toString();
    return hash.substring(0, 8).toUpperCase();
  }
}

class EncryptionException implements Exception {
  final String message;
  const EncryptionException(this.message);

  @override
  String toString() => message;
}
