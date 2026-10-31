/// Human friendly formatting helpers shared across the app.
String formatDuration(Duration duration) {
  if (duration.inMilliseconds <= 0) return '0:00';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  final paddedSeconds = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$paddedSeconds';
  }
  return '$minutes:$paddedSeconds';
}

String formatTotalDuration(Duration duration) {
  if (duration.inMinutes >= 60) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '${hours}h ${minutes}m';
  }
  return '${duration.inMinutes} min';
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String trackCountLabel(int count) => count == 1 ? '1 song' : '$count songs';

String formatRelativeDate(DateTime date, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final difference = current.difference(date);
  if (difference.inMinutes < 1) return 'just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  if (current.year == date.year) {
    return '${date.day}/${date.month}/${date.year}';
  }
  return '${date.day}/${date.month}/${date.year}';
}

String formatPlaybackSpeed(double speed) {
  if (speed == speed.roundToDouble()) return '${speed.toStringAsFixed(0)}x';
  return '${speed.toStringAsFixed(2).replaceAll(RegExp(r'0$'), '')}x';
}
