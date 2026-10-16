import 'dart:typed_data';

import '../auth/api_client.dart';
import 'curation.dart' show ReportReason;
import 'family_catalog.dart';

/// The family side of the catalogue, one method per route: what
/// each child can see, hides per child and reports for the family.
/// Problems surface as `ApiError`; a minor outside the caller's family
/// answers `not_found`, and reports are limited to 20 a day
/// (`rate_limited` with its wait).
class FamilyCatalogApi {
  FamilyCatalogApi(this._client);

  final ApiClient _client;

  static String _id(String id) => Uri.encodeComponent(id);

  Future<FamilyCatalogPage> minorCatalog(
    String minorId, {
    int offset = 0,
  }) async => FamilyCatalogPage.fromJson(
    await _client.send(
      'GET',
      '/v1/family/minors/${_id(minorId)}/catalog?offset=$offset',
    ) as Map<String, dynamic>,
  );

  Future<void> hide(String minorId, String videoId) => _client.send(
    'PUT',
    '/v1/family/minors/${_id(minorId)}/hidden/${_id(videoId)}',
  );

  Future<void> unhide(String minorId, String videoId) => _client.send(
    'DELETE',
    '/v1/family/minors/${_id(minorId)}/hidden/${_id(videoId)}',
  );

  /// Reports a video for the whole family; true when this report is new
  /// (201), false when the family's earlier one stands (200).
  Future<bool> report(
    String videoId,
    ReportReason reason, {
    String? note,
  }) async {
    final r = await _client.sendResponse(
      'POST',
      '/v1/reports',
      body: {'video_id': videoId, 'reason': reason.wire, 'note': ?note},
    );
    return r.statusCode == 201;
  }

  /// A thumbnail's JPEG bytes, through the session.
  Future<Uint8List> thumbnail(String videoId) async =>
      (await _client.sendResponse(
        'GET',
        '/v1/family/thumbs/${_id(videoId)}',
      )).bodyBytes;
}
