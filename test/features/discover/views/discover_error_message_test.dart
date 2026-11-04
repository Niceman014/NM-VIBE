import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nm_vibe/features/discover/views/discover_error_message.dart';

void main() {
  group('discoverErrorMessage', () {
    test('maps HandshakeException to the secure connection message', () {
      expect(
        discoverErrorMessage(const HandshakeException('private detail')),
        secureConnectionErrorMessage,
      );
    });

    test('maps TlsException to the secure connection message', () {
      expect(
        discoverErrorMessage(const TlsException('private detail')),
        secureConnectionErrorMessage,
      );
    });

    test('maps SocketException to the offline message', () {
      expect(
        discoverErrorMessage(const SocketException('private detail')),
        offlineErrorMessage,
      );
    });

    test('maps TimeoutException to the offline message', () {
      expect(
        discoverErrorMessage(TimeoutException('private detail')),
        offlineErrorMessage,
      );
    });

    test('maps ClientException to the offline message', () {
      expect(
        discoverErrorMessage(http.ClientException('private detail')),
        offlineErrorMessage,
      );
    });

    test('hides unclassified exception text', () {
      expect(
        discoverErrorMessage(StateError('private detail')),
        genericDiscoverErrorMessage,
      );
    });
  });
}
