import 'dart:math';

/// Generates and checks the 6-digit pairing PIN. The PIN doubles as the
/// bearer token every API request must present, so anyone on the WiFi
/// network without the PIN can't browse or stream anything, even though
/// the server itself is reachable.
class AuthService {
  String _pin = '';

  String get pin => _pin;

  String generatePin() {
    final rand = Random.secure();
    _pin = List.generate(6, (_) => rand.nextInt(10)).join();
    return _pin;
  }

  /// Constant-time comparison to avoid leaking timing information about
  /// how many leading characters of an incoming token were correct.
  bool verify(String? presented) {
    if (presented == null) return false;
    if (presented.length != _pin.length) return false;
    var diff = 0;
    for (var i = 0; i < _pin.length; i++) {
      diff |= presented.codeUnitAt(i) ^ _pin.codeUnitAt(i);
    }
    return diff == 0;
  }
}
