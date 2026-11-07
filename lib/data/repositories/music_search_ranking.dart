import '../sources/music_source.dart';

final RegExp _searchSeparators = RegExp(r"[^\p{L}\p{N}]+", unicode: true);
final RegExp _searchWhitespace = RegExp(r'\s+');

/// Orders already-matched provider results by how closely title and artist
/// match the query. Provider matching remains responsible for inclusion.
List<MusicTrack> rankMusicTracks(String query, Iterable<MusicTrack> tracks) {
  final normalizedQuery = normalizeMusicSearchText(query);
  if (normalizedQuery.isEmpty) return List<MusicTrack>.unmodifiable(tracks);
  final scorer = MusicSearchScorer(normalizedQuery);
  final ranked =
      tracks.indexed
          .map(
            (entry) => _ScoredTrack(
              entry.$1,
              entry.$2,
              scorer.score(
                normalizeMusicSearchText(entry.$2.title),
                normalizeMusicSearchText(entry.$2.artist),
                album: normalizeMusicSearchText(entry.$2.album),
              ),
            ),
          )
          .toList()
        ..sort((left, right) {
          final scoreDifference = right.score.compareTo(left.score);
          return scoreDifference == 0
              ? left.index.compareTo(right.index)
              : scoreDifference;
        });
  return List<MusicTrack>.unmodifiable(ranked.map((entry) => entry.track));
}

class _ScoredTrack {
  const _ScoredTrack(this.index, this.track, this.score);

  final int index;
  final MusicTrack track;
  final int score;
}

String normalizeMusicSearchText(String value) => value
    .toLowerCase()
    .replaceAll(_searchSeparators, ' ')
    .trim()
    .replaceAll(_searchWhitespace, ' ');

class MusicSearchScorer {
  MusicSearchScorer(String searchQuery)
    : query = normalizeMusicSearchText(searchQuery),
      words = normalizeMusicSearchText(searchQuery)
          .split(' ')
          .where((word) => word.isNotEmpty)
          .toList(growable: false);

  final String query;
  final List<String> words;

  int score(String title, String artist, {String album = ''}) {
    if (title == query) return 1000;
    if (artist == query) return 950;
    if (title.startsWith(query)) return 900;
    if (title.contains(query)) return 800;
    if (artist.startsWith(query)) return 750;
    final titleContainsAll = words.every(title.contains);
    final artistContainsAll = words.every(artist.contains);
    if (titleContainsAll) return 700;
    if (artistContainsAll) return 650;
    if (words.every(album.contains)) return 600;
    final compactQuery = query.replaceAll(' ', '');
    final compactTitle = title.replaceAll(' ', '');
    if (_distanceAtMostOne(compactQuery, compactTitle)) return 350;
    final titleMatched = words.where(title.contains).length;
    final artistMatched = words.where(artist.contains).length;
    final allMatched = words.every(
      (word) => title.contains(word) || artist.contains(word),
    );
    if (allMatched) return 500 + titleMatched * 10 + artistMatched * 5;
    // Typo tolerance only applies when every query word has a close token match.
    final fuzzyTitle = words
        .where((word) => _fieldHasCloseToken(word, title))
        .length;
    final fuzzyArtist = words
        .where((word) => _fieldHasCloseToken(word, artist))
        .length;
    if (words.every(
      (word) =>
          _fieldHasCloseToken(word, title) || _fieldHasCloseToken(word, artist),
    )) {
      return 300 + fuzzyTitle * 5 + fuzzyArtist;
    }
    return 0;
  }
}

bool _fieldHasCloseToken(String queryWord, String field) {
  if (queryWord.length < 3) return false;
  var start = 0;
  for (var index = 0; index <= field.length; index++) {
    if (index != field.length && field.codeUnitAt(index) != 32) continue;
    if (index > start) {
      final candidate = field.substring(start, index);
      final maxEdits = queryWord.length >= 4 && candidate.length >= 6 ? 2 : 1;
      if (_distanceAtMost(queryWord, candidate, maxEdits)) return true;
    }
    start = index + 1;
  }
  return false;
}

bool _distanceAtMostOne(String a, String b) {
  return _distanceAtMost(a, b, 1);
}

bool _distanceAtMost(String a, String b, int maxEdits) {
  if (a.length < 3 || b.length < 2 || (a.length - b.length).abs() > maxEdits) {
    return false;
  }
  var previous = List<int>.generate(b.length + 1, (index) => index);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, maxEdits + 1);
    current[0] = i;
    var rowMinimum = current[0];
    for (var j = 1; j <= b.length; j++) {
      final substitutionCost = a[i - 1] == b[j - 1] ? 0 : 1;
      final value = <int>[
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + substitutionCost,
      ].reduce((left, right) => left < right ? left : right);
      current[j] = value;
      if (value < rowMinimum) rowMinimum = value;
    }
    if (rowMinimum > maxEdits) return false;
    previous = current;
  }
  return previous[b.length] <= maxEdits;
}
