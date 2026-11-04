import 'dart:math' as math;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nm_vibe/core/constants/theme_constants.dart';
import 'package:nm_vibe/data/models/library_groups.dart';
import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/core/utils/formatters.dart';
import 'package:nm_vibe/shared/widgets/album_art.dart';
import 'package:nm_vibe/shared/navigation/open_now_playing.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import 'package:nm_vibe/shared/widgets/empty_state.dart';
import 'package:nm_vibe/shared/widgets/song_tile.dart';
import 'artist_detail_page.dart';

/// Rich album screen: hero artwork, album metadata, play/shuffle and the full
/// track list with the currently playing track highlighted.
class AlbumDetailPage extends ConsumerWidget {
  const AlbumDetailPage({super.key, required this.album});

  /// Snapshot used as a fallback while the live albums provider resolves the
  /// same album key (keeps navigation instant and robust to rescans).
  final AlbumGroup album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 800;
    final sidePadding = width >= 1000
        ? ((width - 960) / 2).clamp(24.0, 480.0)
        : (width >= 600 ? 24.0 : 20.0);

    final liveAlbum = _findAlbum(ref.watch(albumsProvider), album.key) ?? album;
    final player = ref.watch(playerControllerProvider);
    final currentSongId = player.current?.id;
    final songs = liveAlbum.songs;

    final artistGroup = _findArtist(
      ref.watch(artistsProvider),
      liveAlbum.artist,
    );

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(
                scheme.primaryContainer.withValues(alpha: 0.55),
                scheme.surface,
              ),
              scheme.surface,
            ],
            stops: const [0, 0.45],
          ),
        ),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.transparent,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              actions: [
                IconButton(
                  tooltip: 'Add album to queue',
                  icon: const Icon(Icons.queue_music_rounded),
                  onPressed: songs.isEmpty
                      ? null
                      : () => _queueAlbum(context, ref, songs),
                ),
                const SizedBox(width: ThemeConstants.spacing4),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  sidePadding,
                  0,
                  sidePadding,
                  ThemeConstants.spacing8,
                ),
                child: isWide
                    ? _WideHero(
                        album: liveAlbum,
                        onPlay: () => _playAlbum(context, ref, songs),
                        onShuffle: () =>
                            _playAlbum(context, ref, songs, shuffle: true),
                        onArtistTap: artistGroup == null
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      ArtistDetailPage(artist: artistGroup),
                                ),
                              ),
                      )
                    : _NarrowHero(
                        album: liveAlbum,
                        onPlay: () => _playAlbum(context, ref, songs),
                        onShuffle: () =>
                            _playAlbum(context, ref, songs, shuffle: true),
                        onArtistTap: artistGroup == null
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      ArtistDetailPage(artist: artistGroup),
                                ),
                              ),
                      ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  sidePadding + ThemeConstants.spacing8,
                  ThemeConstants.spacing12,
                  sidePadding,
                  ThemeConstants.spacing8,
                ),
                child: Row(
                  children: [
                    Text(
                      'TRACKS',
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${trackCountLabel(songs.length)} · ${formatTotalDuration(liveAlbum.duration)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (songs.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.album_outlined,
                  title: 'Album is empty',
                  message: 'Its songs are no longer in your library.',
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.symmetric(
                  horizontal: sidePadding - ThemeConstants.spacing8,
                ),
                sliver: SliverList.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    final number = song.trackNumber ?? index + 1;
                    return SongTile(
                      song: song,
                      showArtwork: false,
                      artworkSize: 38,
                      leading: Text(
                        number.toString().padLeft(2, '0'),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: song.id == currentSongId
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      isCurrent: song.id == currentSongId,
                      isPlaying: player.playing,
                      subtitle:
                          song.displayArtist.toLowerCase() ==
                              liveAlbum.artist.toLowerCase()
                          ? ''
                          : song.displayArtist,
                      onTap: () {
                        unawaited(
                          playSongsAndOpen(
                            context,
                            ref,
                            songs,
                            initialIndex: index,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            const SliverToBoxAdapter(
              child: SizedBox(height: ThemeConstants.spacing32),
            ),
          ],
        ),
      ),
    );
  }

  static AlbumGroup? _findAlbum(List<AlbumGroup> albums, String key) {
    for (final album in albums) {
      if (album.key == key) return album;
    }
    return null;
  }

  static ArtistGroup? _findArtist(List<ArtistGroup> artists, String name) {
    for (final artist in artists) {
      if (artist.name == name) return artist;
    }
    return null;
  }

  Future<void> _playAlbum(
    BuildContext context,
    WidgetRef ref,
    List<Song> songs, {
    bool shuffle = false,
  }) async {
    if (songs.isEmpty) return;
    final queue = List<Song>.of(songs);
    if (shuffle) queue.shuffle(math.Random());
    final controller = ref.read(playerControllerProvider.notifier);
    final state = ref.read(playerControllerProvider);
    if (shuffle != state.shuffleEnabled) {
      await controller.toggleShuffle();
    }
    if (!context.mounted) return;
    await playSongsAndOpen(context, ref, queue);
  }

  Future<void> _queueAlbum(
    BuildContext context,
    WidgetRef ref,
    List<Song> songs,
  ) async {
    final controller = ref.read(playerControllerProvider.notifier);
    for (final song in songs) {
      await controller.addToQueue(song);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          songs.length == 1
              ? 'Album added to the queue'
              : '${songs.length} songs added to the queue',
        ),
      ),
    );
  }
}

class _WideHero extends StatelessWidget {
  const _WideHero({
    required this.album,
    required this.onPlay,
    required this.onShuffle,
    this.onArtistTap,
  });

  final AlbumGroup album;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final VoidCallback? onArtistTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AlbumArt(
          artworkKey: album.artworkKey,
          size: 236,
          borderRadius: ThemeConstants.radiusLarge,
          semanticLabel: '${album.name} artwork',
        ),
        const SizedBox(width: ThemeConstants.spacing32),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ALBUM',
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 2,
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: ThemeConstants.spacing8),
              Text(
                album.name,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontSize: 44,
                  color: scheme.onSurface,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: ThemeConstants.spacing8),
              _ArtistLine(
                artist: album.artist,
                year: album.year,
                onTap: onArtistTap,
              ),
              const SizedBox(height: ThemeConstants.spacing8),
              Text(
                '${trackCountLabel(album.songs.length)} · ${formatTotalDuration(album.duration)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: ThemeConstants.spacing24),
              _HeroActions(onPlay: onPlay, onShuffle: onShuffle),
            ],
          ),
        ),
      ],
    );
  }
}

class _NarrowHero extends StatelessWidget {
  const _NarrowHero({
    required this.album,
    required this.onPlay,
    required this.onShuffle,
    this.onArtistTap,
  });

  final AlbumGroup album;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final VoidCallback? onArtistTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final artSize = math.min(MediaQuery.sizeOf(context).width * 0.52, 220.0);
    return Column(
      children: [
        const SizedBox(height: ThemeConstants.spacing8),
        AlbumArt(
          artworkKey: album.artworkKey,
          size: artSize,
          borderRadius: ThemeConstants.radiusLarge,
          semanticLabel: '${album.name} artwork',
        ),
        const SizedBox(height: ThemeConstants.spacing24),
        Text(
          'ALBUM',
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 2,
            fontWeight: FontWeight.w800,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: ThemeConstants.spacing8),
        Text(
          album.name,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: ThemeConstants.spacing8),
        _ArtistLine(
          artist: album.artist,
          year: album.year,
          onTap: onArtistTap,
          center: true,
        ),
        const SizedBox(height: ThemeConstants.spacing8),
        Text(
          '${trackCountLabel(album.songs.length)} · ${formatTotalDuration(album.duration)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: ThemeConstants.spacing24),
        _HeroActions(onPlay: onPlay, onShuffle: onShuffle),
      ],
    );
  }
}

class _ArtistLine extends StatelessWidget {
  const _ArtistLine({
    required this.artist,
    this.year,
    this.onTap,
    this.center = false,
  });

  final String artist;
  final int? year;
  final VoidCallback? onTap;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final nameStyle = theme.textTheme.titleMedium?.copyWith(
      color: scheme.primary,
      fontWeight: FontWeight.w700,
    );
    final yearStyle = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Row(
      mainAxisAlignment: center
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        if (onTap != null)
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ThemeConstants.spacing4,
                vertical: ThemeConstants.spacing4,
              ),
              child: Text(artist, style: nameStyle),
            ),
          )
        else
          Text(artist, style: nameStyle),
        if (year != null) ...[
          Text(' · ', style: yearStyle),
          Text('$year', style: yearStyle),
        ],
      ],
    );
  }
}

class _HeroActions extends StatelessWidget {
  const _HeroActions({required this.onPlay, required this.onShuffle});

  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: ThemeConstants.spacing12,
      runSpacing: ThemeConstants.spacing12,
      children: [
        FilledButton.icon(
          onPressed: onPlay,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Play'),
        ),
        FilledButton.tonalIcon(
          onPressed: onShuffle,
          icon: const Icon(Icons.shuffle_rounded),
          label: const Text('Shuffle'),
        ),
      ],
    );
  }
}
