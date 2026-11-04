import 'dart:math' as math;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nm_vibe/core/constants/theme_constants.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nm_vibe/data/models/library_groups.dart';
import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/core/utils/formatters.dart';
import 'package:nm_vibe/shared/widgets/album_art.dart';
import 'package:nm_vibe/shared/navigation/open_now_playing.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import '../widgets/collection_cards.dart';
import 'package:nm_vibe/shared/widgets/empty_state.dart';
import 'package:nm_vibe/shared/widgets/song_tile.dart';
import 'album_detail_page.dart';

/// Artist screen: round portrait hero, album strip and every track by the
/// artist in one calm list.
class ArtistDetailPage extends ConsumerWidget {
  const ArtistDetailPage({super.key, required this.artist});

  final ArtistGroup artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 800;
    final sidePadding = width >= 1000
        ? ((width - 960) / 2).clamp(24.0, 480.0)
        : (width >= 600 ? 24.0 : 20.0);

    final liveArtist =
        _findArtist(ref.watch(artistsProvider), artist.name) ?? artist;
    final player = ref.watch(playerControllerProvider);
    final currentSongId = player.current?.id;
    final artistAlbums = groupAlbums(liveArtist.songs);
    final songs = liveArtist.songs;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(
                scheme.secondaryContainer.withValues(alpha: 0.5),
                scheme.surface,
              ),
              scheme.surface,
            ],
            stops: const [0, 0.42],
          ),
        ),
        child: CustomScrollView(
          slivers: [
            const SliverAppBar(
              pinned: true,
              backgroundColor: Colors.transparent,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  sidePadding,
                  0,
                  sidePadding,
                  ThemeConstants.spacing12,
                ),
                child: isWide
                    ? _WideArtistHero(
                        artist: liveArtist,
                        onPlay: () => _playArtist(context, ref, songs),
                        onShuffle: () =>
                            _playArtist(context, ref, songs, shuffle: true),
                      )
                    : _NarrowArtistHero(
                        artist: liveArtist,
                        onPlay: () => _playArtist(context, ref, songs),
                        onShuffle: () =>
                            _playArtist(context, ref, songs, shuffle: true),
                      ),
              ),
            ),
            if (artistAlbums.length > 1) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    sidePadding + ThemeConstants.spacing8,
                    ThemeConstants.spacing4,
                    sidePadding,
                    ThemeConstants.spacing4,
                  ),
                  child: Text(
                    'ALBUMS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 208,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(
                      horizontal: sidePadding - ThemeConstants.spacing4,
                    ),
                    itemCount: artistAlbums.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: ThemeConstants.spacing8),
                    itemBuilder: (context, index) {
                      final album = artistAlbums[index];
                      return AlbumStripCard(
                        album: album,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => AlbumDetailPage(album: album),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  sidePadding + ThemeConstants.spacing8,
                  ThemeConstants.spacing16,
                  sidePadding,
                  ThemeConstants.spacing8,
                ),
                child: Row(
                  children: [
                    Text(
                      'SONGS',
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      trackCountLabel(songs.length),
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
                  icon: Icons.person_outline_rounded,
                  title: 'No songs',
                  message: 'This artist has no songs in your library.',
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
                    return SongTile(
                      song: song,
                      isCurrent: song.id == currentSongId,
                      isPlaying: player.playing,
                      subtitle: song.displayAlbum,
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

  static ArtistGroup? _findArtist(List<ArtistGroup> artists, String name) {
    for (final artist in artists) {
      if (artist.name == name) return artist;
    }
    return null;
  }

  Future<void> _playArtist(
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
}

class _WideArtistHero extends StatelessWidget {
  const _WideArtistHero({
    required this.artist,
    required this.onPlay,
    required this.onShuffle,
  });

  final ArtistGroup artist;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AlbumArt(
          artworkKey: artist.artworkKey,
          size: 224,
          borderRadius: 112,
          semanticLabel: '${artist.name} artwork',
        ),
        const SizedBox(width: ThemeConstants.spacing32),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ARTIST',
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 2,
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: ThemeConstants.spacing8),
              Text(
                artist.name,
                style: theme.textTheme.displaySmall?.copyWith(fontSize: 44),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: ThemeConstants.spacing8),
              Text(
                '${artist.albumCount == 1 ? '1 album' : '${artist.albumCount} albums'} · ${trackCountLabel(artist.songs.length)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: ThemeConstants.spacing24),
              _ArtistActions(onPlay: onPlay, onShuffle: onShuffle),
            ],
          ),
        ),
      ],
    );
  }
}

class _NarrowArtistHero extends StatelessWidget {
  const _NarrowArtistHero({
    required this.artist,
    required this.onPlay,
    required this.onShuffle,
  });

  final ArtistGroup artist;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final diameter = math.min(MediaQuery.sizeOf(context).width * 0.5, 200.0);
    return Column(
      children: [
        const SizedBox(height: ThemeConstants.spacing8),
        AlbumArt(
          artworkKey: artist.artworkKey,
          size: diameter,
          borderRadius: diameter / 2,
          semanticLabel: '${artist.name} artwork',
        ),
        const SizedBox(height: ThemeConstants.spacing24),
        Text(
          'ARTIST',
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 2,
            fontWeight: FontWeight.w800,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: ThemeConstants.spacing8),
        Text(
          artist.name,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: ThemeConstants.spacing8),
        Text(
          '${artist.albumCount == 1 ? '1 album' : '${artist.albumCount} albums'} · ${trackCountLabel(artist.songs.length)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: ThemeConstants.spacing24),
        _ArtistActions(onPlay: onPlay, onShuffle: onShuffle),
      ],
    );
  }
}

class _ArtistActions extends StatelessWidget {
  const _ArtistActions({required this.onPlay, required this.onShuffle});

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
