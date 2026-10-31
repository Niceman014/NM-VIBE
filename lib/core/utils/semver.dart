/// A parsed Semantic Versioning 2.0.0 value.
///
/// Build metadata is retained for display but intentionally ignored when
/// comparing precedence. [tryParse] returns `null` for malformed values and
/// never throws.
final class SemVer implements Comparable<SemVer> {
  const SemVer._({
    required this.major,
    required this.minor,
    required this.patch,
    required this.prerelease,
    required this.build,
  });

  static final RegExp _pattern = RegExp(
    r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
    r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?'
    r'(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$',
  );

  final BigInt major;
  final BigInt minor;
  final BigInt patch;
  final List<String> prerelease;
  final List<String> build;

  static SemVer? tryParse(String? input) {
    if (input == null) return null;
    try {
      final match = _pattern.firstMatch(input.trim());
      if (match == null) return null;
      final prereleaseText = match.group(4);
      final buildText = match.group(5);
      final prerelease = prereleaseText?.split('.') ?? const <String>[];
      final build = buildText?.split('.') ?? const <String>[];
      if (prerelease.any(_hasLeadingZeroNumericIdentifier)) return null;
      return SemVer._(
        major: BigInt.parse(match.group(1)!),
        minor: BigInt.parse(match.group(2)!),
        patch: BigInt.parse(match.group(3)!),
        prerelease: List<String>.unmodifiable(prerelease),
        build: List<String>.unmodifiable(build),
      );
    } on FormatException {
      return null;
    } catch (_) {
      // Treat all malformed or unexpectedly unrepresentable input as invalid.
      return null;
    }
  }

  static bool _hasLeadingZeroNumericIdentifier(String value) =>
      RegExp(r'^0[0-9]+$').hasMatch(value);

  @override
  int compareTo(SemVer other) {
    final majorOrder = major.compareTo(other.major);
    if (majorOrder != 0) return majorOrder;
    final minorOrder = minor.compareTo(other.minor);
    if (minorOrder != 0) return minorOrder;
    final patchOrder = patch.compareTo(other.patch);
    if (patchOrder != 0) return patchOrder;

    if (prerelease.isEmpty || other.prerelease.isEmpty) {
      if (prerelease.isEmpty && other.prerelease.isEmpty) return 0;
      return prerelease.isEmpty ? 1 : -1;
    }

    final sharedLength = prerelease.length < other.prerelease.length
        ? prerelease.length
        : other.prerelease.length;
    for (var index = 0; index < sharedLength; index++) {
      final left = prerelease[index];
      final right = other.prerelease[index];
      final leftNumeric = _isNumeric(left);
      final rightNumeric = _isNumeric(right);
      if (leftNumeric && rightNumeric) {
        final order = BigInt.parse(left).compareTo(BigInt.parse(right));
        if (order != 0) return order;
      } else if (leftNumeric != rightNumeric) {
        return leftNumeric ? -1 : 1;
      } else {
        final order = left.compareTo(right);
        if (order != 0) return order;
      }
    }
    return prerelease.length.compareTo(other.prerelease.length);
  }

  static bool _isNumeric(String value) => RegExp(r'^[0-9]+$').hasMatch(value);

  @override
  String toString() =>
      '$major.$minor.$patch'
      '${prerelease.isEmpty ? '' : '-${prerelease.join('.')}'}'
      '${build.isEmpty ? '' : '+${build.join('.')}'}';
}

/// Returns `null` when either version is malformed.
int? compareSemVer(String? left, String? right) {
  final parsedLeft = SemVer.tryParse(left);
  final parsedRight = SemVer.tryParse(right);
  if (parsedLeft == null || parsedRight == null) return null;
  return parsedLeft.compareTo(parsedRight);
}
