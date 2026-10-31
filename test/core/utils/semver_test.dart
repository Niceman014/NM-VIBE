import 'package:flutter_test/flutter_test.dart';
import 'package:nm_vibe/core/utils/semver.dart';

void main() {
  group('SemVer.tryParse', () {
    test('parses a stable version', () {
      final version = SemVer.tryParse('1.0.0');
      expect(version, isNotNull);
      expect(version.toString(), '1.0.0');
    });

    test('parses build metadata such as a package build number', () {
      final version = SemVer.tryParse('1.0.0+5');
      expect(version, isNotNull);
      expect(version.toString(), '1.0.0+5');
    });

    test('parses dotted prerelease identifiers', () {
      final version = SemVer.tryParse('1.0.0-beta.2');
      expect(version, isNotNull);
      expect(version.toString(), '1.0.0-beta.2');
    });

    test('returns null for malformed input without throwing', () {
      expect(() => SemVer.tryParse('not-a-version'), returnsNormally);
      expect(SemVer.tryParse('not-a-version'), isNull);
      expect(SemVer.tryParse('1.0'), isNull);
      expect(SemVer.tryParse('01.0.0'), isNull);
      expect(SemVer.tryParse('1.0.0-beta.02'), isNull);
      expect(SemVer.tryParse(null), isNull);
    });
  });

  group('SemVer precedence', () {
    test('compares major, minor and patch numerically', () {
      expect(compareSemVer('2.0.0', '1.99.99'), greaterThan(0));
      expect(compareSemVer('1.10.0', '1.9.9'), greaterThan(0));
      expect(compareSemVer('1.0.2', '1.0.10'), lessThan(0));
    });

    test('prerelease sorts before stable and numeric identifiers compare', () {
      expect(compareSemVer('1.0.0-beta.2', '1.0.0'), lessThan(0));
      expect(compareSemVer('1.0.0-beta.10', '1.0.0-beta.2'), greaterThan(0));
      expect(compareSemVer('1.0.0-alpha', '1.0.0-beta'), lessThan(0));
    });

    test('build metadata does not change precedence', () {
      expect(compareSemVer('1.0.0+5', '1.0.0+6'), 0);
    });

    test('invalid comparison input returns null', () {
      expect(compareSemVer('bad', '1.0.0'), isNull);
    });
  });
}
