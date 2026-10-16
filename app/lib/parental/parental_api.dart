import '../auth/api_client.dart';
import 'parental.dart';

/// The guardian routes, one method per endpoint. Problems
/// surface as `ApiError`; on `reauth_required` the screen re-authenticates
/// and retries.
class ParentalApi {
  ParentalApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Object? body,
  }) async =>
      await _client.send(method, path, body: body) as Map<String, dynamic>;

  Future<bool> pinIsSet() async =>
      (await _json('GET', '/v1/parental/pin'))['set'] as bool;

  /// Sets or replaces the family PIN. Needs a re-authentication within the
  /// last 5 minutes.
  Future<void> setPin(String pin) =>
      _client.send('PUT', '/v1/parental/pin', body: {'pin': pin});

  /// Checks the family PIN for an unlocked session; shares the counter
  /// and cooldown of unlock and the picker.
  Future<void> verifyPin(String pin) =>
      _client.send('POST', '/v1/parental/pin/verify', body: {'pin': pin});

  /// Locks this device's session to the child ("entregar para"): from
  /// here on only the child routes and the PIN answer it.
  Future<void> handOver(String minorId) => _client.send(
    'POST',
    '/v1/parental/kid-mode',
    body: {'minor_id': minorId},
  );

  Future<LinkCode> createLinkCode(String minorId) async => LinkCode.fromJson(
    await _json('POST', '/v1/parental/link-codes', body: {'minor_id': minorId}),
  );

  Future<List<LinkedDevice>> devices() async => [
    for (final d
        in (await _json('GET', '/v1/parental/devices'))['devices']
            as List<dynamic>)
      LinkedDevice.fromJson(d as Map<String, dynamic>),
  ];

  Future<void> unlink(String id) =>
      _client.send('DELETE', '/v1/parental/devices/${Uri.encodeComponent(id)}');
}
