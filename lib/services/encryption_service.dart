import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

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
    final keyBytes = sha256.convert(utf8.encode(passphrase)).bytes;
    _key = enc.Key(Uint8List.fromList(keyBytes));
    _encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.cbc));
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
      throw EncryptionException('Encryption failed: $e');
    }
  }

  /// Decrypts payload. Tries v2 (Random IV) then v1 (Legacy Static IV).
  String decrypt(String payload) {
    try {
      final combined = base64.decode(payload);
      if (combined.length >= 17) {
        final iv = enc.IV(Uint8List.fromList(combined.sublist(0, 16)));
        final cipher = enc.Encrypted(Uint8List.fromList(combined.sublist(16)));
        return _encrypter.decrypt(cipher, iv: iv);
      }
    } catch (_) {
      // Fallback to legacy path
    }
    return _decryptLegacy(payload);
  }

  String _decryptLegacy(String ciphertext) {
    try {
      final ivBytes = md5.convert(utf8.encode(_passphrase)).bytes;
      final iv = enc.IV(Uint8List.fromList(ivBytes));
      final encrypted = enc.Encrypted.fromBase64(ciphertext);
      return _encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      throw EncryptionException('Decryption failed: Key mismatch.');
    }
  }

  void updatePassphrase(String newPassphrase) => _initKey(newPassphrase);

  static String generatePassphrase() {
    final bytes = enc.SecureRandom(18).bytes;
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String hashPreview(String passphrase) {
    if (passphrase.isEmpty) return '00000000';
    return sha256
        .convert(utf8.encode(passphrase))
        .toString()
        .substring(0, 8)
        .toUpperCase();
  }
}

class EncryptionException implements Exception {
  final String message;
  const EncryptionException(this.message);
  @override
  String toString() => message;
}
