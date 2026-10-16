import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../auth/api_client.dart';
import '../auth/api_error.dart';
import '../curation/kid_catalog.dart';
import '../screentime/kid_time.dart';
import 'device_credential_store.dart';
import 'parental.dart';

/// The child routes, plus redemption. A linked device
/// sends its device token; otherwise the call rides the guardian's
/// session, which the server only accepts while it is locked to a child.
class ChildApi {
  ChildApi(this._client, {this._devices});

  final ApiClient _client;
  final DeviceCredentialStore? _devices;

  Future<bool> isLinked() async => await _devices?.read() != null;

  /// Only Android and iOS keep a device credential,
  /// so only they redeem a link code: not the web,
  /// which has no store, nor a desktop, which has one but is no child's.
  bool get canLink =>
      _devices != null &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<Object?> _send(String method, String path, {Object? body}) async {
    final response = await _sendResponse(method, path, body: body);
    return response.body.isEmpty ? null : jsonDecode(response.body);
  }

  Future<http.Response> _sendResponse(
    String method,
    String path, {
    Object? body,
  }) async {
    final token = await _devices?.read();
    if (token == null) return _session(method, path, body);
    try {
      return await _client.sendAsResponse(token, method, path, body: body);
    } on ApiError catch (e) {
      // Unlinked, or idle for 180 days: the token is dead.
      if (e.status == 401) await _devices!.clear();
      rethrow;
    }
  }

  /// On the web the cookie session has no refresh, so a `401` here would
  /// otherwise wait for a reload to sign out; a wrong PIN is a `403` and
  /// keeps it.
  Future<http.Response> _session(
    String method,
    String path,
    Object? body,
  ) async {
    try {
      return await _client.sendResponse(method, path, body: body);
    } on ApiError catch (e) {
      if (e.status == 401 && _client.kind == ClientKind.web) {
        await _client.forgetSession();
      }
      rethrow;
    }
  }

  static String _id(String id) => Uri.encodeComponent(id);

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Object? body,
  }) async => await _send(method, path, body: body) as Map<String, dynamic>;

  Future<Profile> profile() async =>
      Profile.fromJson(await _json('GET', '/v1/child/profile'));

  /// Leaves kid mode on a shared device.
  Future<void> unlock(String pin) =>
      _send('POST', '/v1/child/unlock', body: {'pin': pin});

  /// A linked device's profile picker, behind the PIN.
  Future<List<Profile>> profiles(String pin) async => [
    for (final p
        in (await _json(
              'POST',
              '/v1/child/profiles',
              body: {'pin': pin},
            ))['profiles']
            as List<dynamic>)
      Profile.fromJson(p as Map<String, dynamic>),
  ];

  /// Re-binds a linked device to another child, behind the PIN.
  Future<Profile> switchProfile({
    required String pin,
    required String minorId,
  }) async => Profile.fromJson(
    await _json(
      'PUT',
      '/v1/child/profile',
      body: {'pin': pin, 'minor_id': minorId},
    ),
  );

  /// The child's theme shelves.
  Future<KidCatalog> catalog() async =>
      KidCatalog.fromJson(await _json('GET', '/v1/child/catalog'));

  /// A thumbnail's JPEG bytes, from our API only: kid mode never asks
  /// YouTube for images.
  Future<Uint8List> thumbnail(String videoId) async => (await _sendResponse(
    'GET',
    '/v1/child/thumbs/${_id(videoId)}',
  )).bodyBytes;

  /// Re-checks a video and opens a play: its id for the beats and the
  /// YouTube id for the player. A day without time answers `time_up`.
  Future<KidPlay> play(String videoId) async => KidPlay.fromJson(
    await _json('POST', '/v1/child/plays', body: {'video_id': videoId}),
  );

  /// Tells the server the play is still going ([playing]) or stopped;
  /// answers the day.
  Future<KidTime> beat(String playId, {required bool playing}) async =>
      KidTime.fromJson(
        await _json(
          'POST',
          '/v1/child/plays/${_id(playId)}/beat',
          body: {'playing': playing},
        ),
      );

  /// More time today, behind the parents' PIN.
  Future<KidTime> extend({required String pin, required int minutes}) async =>
      KidTime.fromJson(
        await _json(
          'POST',
          '/v1/child/time/extend',
          body: {'pin': pin, 'minutes': minutes},
        ),
      );

  /// Tells the server the player could not play the video; the server
  /// decides what to do about it.
  Future<void> reportUnavailable(String videoId) =>
      _send('POST', '/v1/child/videos/${_id(videoId)}/unavailable');

  /// Redeems a link code and keeps the device token. Sends no session
  /// credential: the device has none of its own yet.
  Future<Profile> redeem({required String code, required String label}) async {
    final devices = _devices;
    if (devices == null) {
      throw UnsupportedError('Linking a device needs Android or iOS.');
    }
    final body = await _client.send(
      'POST',
      '/v1/devices/redeem',
      body: {'code': code, 'label': label},
      auth: false,
    ) as Map<String, dynamic>;
    await devices.write(body['token'] as String);
    return Profile.fromJson(body['profile'] as Map<String, dynamic>);
  }
}
