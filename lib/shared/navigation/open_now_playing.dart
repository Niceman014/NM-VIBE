import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/features/player/views/now_playing_page.dart' as player;

/// Opens the existing Now Playing route from shared widgets.
void openNowPlaying(BuildContext context) => player.openNowPlaying(context);

/// Plays a song list and opens the existing Now Playing route with its original timing.
Future<void> playSongsAndOpen(
  BuildContext context,
  WidgetRef ref,
  List<Song> songs, {
  int initialIndex = 0,
}) async {
  final controller = ref.read(playerControllerProvider.notifier);
  await controller.playSongs(
    songs,
    initialIndex: initialIndex,
    autoPlay: false,
  );
  if (!context.mounted) return;

  openNowPlaying(context);
  await Future<void>.delayed(const Duration(milliseconds: 460));
  if (!context.mounted || ref.read(playerControllerProvider).error != null) {
    return;
  }
  unawaited(controller.togglePlayPause());
}
