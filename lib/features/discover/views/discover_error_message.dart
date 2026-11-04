import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

const String secureConnectionErrorMessage =
    'Could not make a secure connection. A VPN, proxy or antivirus may be blocking it. Check your network and try again.';

const String offlineErrorMessage =
    'You seem to be offline. Check your connection and try again.';

const String genericDiscoverErrorMessage = 'Could not load music.';

String discoverErrorMessage(Object error) {
  if (error is HandshakeException || error is TlsException) {
    return secureConnectionErrorMessage;
  }
  if (error is SocketException ||
      error is TimeoutException ||
      error is http.ClientException) {
    return offlineErrorMessage;
  }
  return genericDiscoverErrorMessage;
}
