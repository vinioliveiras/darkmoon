import 'package:flutter/material.dart';

import 'editor_screen.dart';
import 'theme.dart';

void main() {
  runApp(const DarkmoonApp());
}

class DarkmoonApp extends StatelessWidget {
  const DarkmoonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Darkmoon',
      debugShowCheckedModeBanner: false,
      theme: buildDarkmoonTheme(),
      home: const EditorScreen(),
    );
  }
}
