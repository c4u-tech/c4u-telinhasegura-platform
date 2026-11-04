import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/curation/shared_link.dart';

void main() {
  group('youtubeLinkIn', () {
    for (final (text, link) in [
      ('https://youtu.be/dQw4w9WgXcQ?si=abc', 'https://youtu.be/dQw4w9WgXcQ'),
      (
        'Peppa Pig - Episódio https://youtu.be/dQw4w9WgXcQ?si=x',
        'https://youtu.be/dQw4w9WgXcQ',
      ),
      (
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ&si=x&t=30',
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ&t=30',
      ),
      (
        'https://www.youtu.be/dQw4w9WgXcQ?si=x',
        'https://www.youtu.be/dQw4w9WgXcQ',
      ),
      (
        'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ',
        'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ',
      ),
      (
        'https://youtube-nocookie.com/embed/dQw4w9WgXcQ',
        'https://youtube-nocookie.com/embed/dQw4w9WgXcQ',
      ),
      (
        'veja https://example.com/a e https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      ),
    ]) {
      test(text, () => expect(youtubeLinkIn(text), link));
    }
    for (final text in [
      null,
      '',
      'só texto',
      'https://example.com/watch?v=dQw4w9WgXcQ',
      'https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ',
      'ftp://youtu.be/dQw4w9WgXcQ',
      'javascript:alert(1)',
      'https://youtu.be/dQw4w9WgXcQ ${'x' * 2048}',
    ]) {
      test('$text has no link', () => expect(youtubeLinkIn(text), isNull));
    }
  });
}
