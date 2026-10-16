import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/curation/curation.dart';
import 'package:telinha_segura/curation/family_catalog.dart';
import 'package:telinha_segura/curation/kid_catalog.dart';

void main() {
  test('the kid catalogue parses its pacotinhos', () {
    final c = KidCatalog.fromJson({
      'themes': <Object>[],
      'packs': [
        {
          'id': 'p1',
          'title': 'Bichos',
          'cover_video_id': 'v3',
          'videos': [
            {'id': 'v1', 'title': 'Baby Shark', 'duration_seconds': 300},
            {'id': 'v3', 'title': 'Sapo', 'duration_seconds': 180},
          ],
        },
      ],
    });
    final p = c.packs.single;
    expect(p.id, 'p1');
    expect(p.title, 'Bichos');
    expect(p.coverVideoId, 'v3');
    expect(p.videos.map((v) => v.id), ['v1', 'v3']);
    expect(p.videos.last.duration, const Duration(minutes: 3));
  });

  test('a kid catalogue without packs reads as none', () {
    expect(KidCatalog.fromJson({'themes': <Object>[]}).packs, isEmpty);
  });

  test('the family catalogue parses its pacotinhos', () {
    final page = FamilyCatalogPage.fromJson({
      'videos': <Object>[],
      'has_more': false,
      'packs': [
        {
          'id': 'p1',
          'title': 'Bichos',
          'cover_video_id': 'v1',
          'composer_role': 'pedagogo',
          'videos': [
            {
              'id': 'v1',
              'title': 'Baby Shark',
              'duration_seconds': 300,
              'hidden': false,
            },
            {
              'id': 'v2',
              'title': 'Galinha',
              'duration_seconds': 240,
              'hidden': true,
            },
          ],
          'provenance': {
            'approvals': {'mae-pai': 2},
            'last_reviewed_at': '2026-10-05T12:00:00Z',
          },
        },
      ],
    });
    final p = page.packs.single;
    expect(p.id, 'p1');
    expect(p.title, 'Bichos');
    expect(p.coverVideoId, 'v1');
    expect(p.composerRole, DisplayRole.pedagogo);
    expect(p.videos.map((v) => v.hidden), [false, true]);
    expect(p.videos.last.duration, const Duration(minutes: 4));
    expect(p.provenance.approvals, {DisplayRole.maePai: 2});
    expect(p.provenance.lastReviewedAt, DateTime.utc(2026, 10, 5, 12));
  });

  test('a family page without packs reads as none', () {
    expect(
      FamilyCatalogPage.fromJson({'videos': <Object>[], 'has_more': true})
          .packs,
      isEmpty,
    );
  });
}
