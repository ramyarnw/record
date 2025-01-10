import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:record_audio/recorder.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  String? audioPath;

  @override
  void initState() {
    super.initState();
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Recorder(
        onStop: (path) {
          if (kDebugMode) print('Recorded file path: $path');
          setState(() {
            audioPath = path;
            //showPlayer = true;
          });
        },
      ),
    );
  }
}
