import 'package:flutter/material.dart';

import 'features/library/views/library_page.dart';

class NmVibeApp extends StatelessWidget {
  const NmVibeApp({super.key});

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFF6750A4);

    return MaterialApp(
      title: 'NM VIBE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: brandColor),
        useMaterial3: true,
      ),
      home: const LibraryPage(),
    );
  }
}
