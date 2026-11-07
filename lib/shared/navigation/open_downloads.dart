import 'package:flutter/material.dart';
import 'package:nm_vibe/features/downloads/views/downloads_page.dart';

/// Opens the saved music library from another feature.
void openDownloads(BuildContext context) {
  Navigator.of(
    context,
  ).push<void>(MaterialPageRoute<void>(builder: (_) => const DownloadsPage()));
}
