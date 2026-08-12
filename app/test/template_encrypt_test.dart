import 'package:encrypt/encrypt.dart' as enc;
import 'package:face_attendance/recognition/template_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('template bundle encryption', () {
    test('64-hex key yields a valid AES-256 key (32 bytes)', () {
      final hexKey = '0123456789abcdef' * 4; // 64 chars
      final key = TemplateStore.aesKeyFromHex(hexKey);
      expect(key.bytes.length, 32);
      expect(key.bytes[0], 0x01);
      expect(key.bytes[31], 0xef);
    });

    test('encrypt/decrypt roundtrip works with the real key format', () {
      final key = TemplateStore.aesKeyFromHex(
          List.generate(64, (i) => 'abcdef'[i % 6]).join());
      final iv = enc.IV.fromSecureRandom(16);
      final encrypter = enc.Encrypter(enc.AES(key));
      const plain = 'hello world';
      final ct = encrypter.encrypt(plain, iv: iv);
      final dec = encrypter.decrypt64(ct.base64, iv: iv);
      expect(dec, plain);
    });

    test('key length is exactly 256 bits (the historical bug)', () {
      final key = TemplateStore.aesKeyFromHex(
          List.generate(64, (_) => 'a').join());
      // AES block cipher accepts 16/24/32-byte keys; 32 bytes = AES-256.
      expect(key.bytes.length, 32);
      expect(() => enc.AES(key), returnsNormally);
    });
  });
}
