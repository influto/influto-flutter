import 'dart:math';

final Random _rng = Random.secure();

/// RFC4122 v4 UUID, zero-dependency (mirrors the RN SDK's hand-rolled generator).
/// Used as the `eventId` idempotency key — the threat model is "host fires the same
/// event twice in a millisecond", not adversarial collision.
String generateUuidV4() {
  const hex = '0123456789abcdef';
  final b = StringBuffer();
  for (var i = 0; i < 36; i++) {
    switch (i) {
      case 8:
      case 13:
      case 18:
      case 23:
        b.write('-');
      case 14:
        b.write('4'); // version 4
      case 19:
        b.write(hex[(_rng.nextInt(16) & 0x3) | 0x8]); // variant 10xx
      default:
        b.write(hex[_rng.nextInt(16)]);
    }
  }
  return b.toString();
}
