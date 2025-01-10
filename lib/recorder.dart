import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pcmtowave/convertToWav.dart';
import 'package:record/record.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;

import 'audio_recorder_io.dart';

class Recorder extends StatefulWidget {
  final void Function(String path) onStop;

  const Recorder({super.key, required this.onStop});

  @override
  State<Recorder> createState() => _RecorderState();
}

class _RecorderState extends State<Recorder> with AudioRecorderMixin {
  int _recordDuration = 0;
  Timer? _timer;
  late final AudioRecorder _audioRecorder;
  StreamSubscription<RecordState>? _recordSub;
  RecordState _recordState = RecordState.stop;
  Status _currentState = Status.peak;
  StreamSubscription<Amplitude>? _amplitudeSub;
  late StreamSubscription<List<Uint8List>> _recordAddSub;
  Amplitude? _amplitude;

  double volume = 0.0;
  double minVolume = -35.0;
  String s = '';

  @override
  void initState() {
    _audioRecorder = AudioRecorder();

    _recordSub = _audioRecorder.onStateChanged().listen((recordState) {
      _updateRecordState(recordState);
    });
    setPcmConverter();
    _amplitudeSub = _audioRecorder
        .onAmplitudeChanged(const Duration(milliseconds: 300))
        .listen((amp) {
      setState(() => _amplitude = amp);
      var currentAmp = _amplitude?.current ?? 0.0;
      if (currentAmp < minVolume) {
        Future.delayed(Duration(milliseconds: 300), onSilence);
      } else {
        onPeak();
      }
    });
    super.initState();
  }

  Future<void> groq(String b) async {
    http.MultipartRequest req = http.MultipartRequest(
      "POST",
      Uri.parse("https://api.groq.com/openai/v1/audio/transcriptions"),
    );
    req.headers['Authorization'] =
        'Bearer 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';
    req.headers["Content-Type"] = 'multipart/form-data';
    req.files.add(await http.MultipartFile.fromPath(
      'file',
      b,
    ));
    req.fields["model"] = "whisper-large-v3";
    var response = await req.send();
    response.stream.transform(utf8.decoder).listen((value) {
      //print(' data ${jsonDecode(value)["text"]}');
      var txt = '${jsonDecode(value)["text"]}';
      if (txt != 'null') {
        s += txt;
      }
      print('s: $s');
    });
  }

  Future<void> setPcmConverter() async {
    final _pcmtowave = convertToWav(
        sampleRate: 44100,
        converMiliSeconds: 100, //convert every 1 sec
        numChannels: 2);
    String path = '';
    File? file;

    _recordAddSub = processData.listen((data) async {
      path = await _getPath();
      print('path: $path');

      file = File(path);
      //move here

      for (var d in data) {
        _pcmtowave.run(d);
      }
    });

    _pcmtowave.convert.listen((data) async {
      //if (file != null) {
        await file!.writeAsBytes(data, mode: FileMode.append);
      //}

      //await groq(path);
    });
    _pcmtowave.dispose();
  }

  void onSilence() {
    setState(() => _currentState = Status.silence);
  }

  void onPeak() {
    setState(() => _currentState = Status.peak);
  }

  Future<void> _start() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        const encoder = AudioEncoder.pcm16bits;

        if (!await _isEncoderSupported(encoder)) {
          return;
        }

        final devs = await _audioRecorder.listInputDevices();
        debugPrint(devs.toString());

        const config = RecordConfig(
          encoder: encoder,
          numChannels: 2,
        );

        // Record to file
        // await recordFile(_audioRecorder, config);

        // Record to stream
        await recordStream(_audioRecorder, config);

        _recordDuration = 0;

        _startTimer();
      }
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
  }

  Future<void> _stop() async {
    final path = await _audioRecorder.stop();
    wholeDataList = [];
    listData = [];
    mapData.clear();
    _recordState = RecordState.stop;
    //print('path: $path');
    if (path != null) {
      widget.onStop(path);
    }
  }

  Future<void> _pause() => _audioRecorder.pause();

  Future<void> _resume() => _audioRecorder.resume();

  void _updateRecordState(RecordState recordState) {
    setState(() => _recordState = recordState);

    switch (recordState) {
      case RecordState.pause:
        _timer?.cancel();
        break;
      case RecordState.record:
        _startTimer();
        break;
      case RecordState.stop:
        _timer?.cancel();
        _recordDuration = 0;
        break;
    }
  }

  Future<bool> _isEncoderSupported(AudioEncoder encoder) async {
    final isSupported = await _audioRecorder.isEncoderSupported(
      encoder,
    );

    if (!isSupported) {
      debugPrint('${encoder.name} is not supported on this platform.');
      debugPrint('Supported encoders are:');

      for (final e in AudioEncoder.values) {
        if (await _audioRecorder.isEncoderSupported(e)) {
          debugPrint('- ${e.name}');
        }
      }
    }

    return isSupported;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _buildRecordStopControl(),
                const SizedBox(width: 20),
                _buildPauseResumeControl(),
                const SizedBox(width: 20),
                _buildText(),
              ],
            ),
            if (_amplitude != null) ...[
              const SizedBox(height: 40),
              Text('Current: ${_amplitude?.current ?? 0.0}'),
              Text('Max: ${_amplitude?.max ?? 0.0}'),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recordSub?.cancel();
    _amplitudeSub?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  Widget _buildRecordStopControl() {
    late Icon icon;
    late Color color;

    if (_recordState != RecordState.stop) {
      icon = const Icon(Icons.stop, color: Colors.red, size: 30);
      color = Colors.red.withOpacity(0.1);
    } else {
      final theme = Theme.of(context);
      icon = Icon(Icons.mic, color: theme.primaryColor, size: 30);
      color = theme.primaryColor.withOpacity(0.1);
    }

    return ClipOval(
      child: Material(
        color: color,
        child: InkWell(
          child: SizedBox(width: 56, height: 56, child: icon),
          onTap: () {
            (_recordState != RecordState.stop) ? _stop() : _start();
          },
        ),
      ),
    );
  }

  Widget _buildPauseResumeControl() {
    if (_recordState == RecordState.stop) {
      return const SizedBox.shrink();
    }

    late Icon icon;
    late Color color;

    if (_recordState == RecordState.record) {
      icon = const Icon(Icons.pause, color: Colors.red, size: 30);
      color = Colors.red.withOpacity(0.1);
    } else {
      final theme = Theme.of(context);
      icon = const Icon(Icons.play_arrow, color: Colors.red, size: 30);
      color = theme.primaryColor.withOpacity(0.1);
    }

    return ClipOval(
      child: Material(
        color: color,
        child: InkWell(
          child: SizedBox(width: 56, height: 56, child: icon),
          onTap: () {
            (_recordState == RecordState.pause) ? _resume() : _pause();
          },
        ),
      ),
    );
  }

  Widget _buildText() {
    if (_recordState != RecordState.stop) {
      return _buildTimer();
    }

    return const Text("Waiting to record");
  }

  Widget _buildTimer() {
    final String minutes = _formatNumber(_recordDuration ~/ 60);
    final String seconds = _formatNumber(_recordDuration % 60);

    return Text(
      '$minutes : $seconds',
      style: const TextStyle(color: Colors.red),
    );
  }

  String _formatNumber(int number) {
    String numberStr = number.toString();
    if (number < 10) {
      numberStr = '0$numberStr';
    }

    return numberStr;
  }

  void _startTimer() {
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      setState(() {
        _recordDuration++;
        updateVolume();
      });
    });
    // _timer ??= Timer.periodic(
    //     const Duration(milliseconds: 50), (timer) => updateVolume());
  }

  updateVolume() async {
    Amplitude? ampl = _amplitude;
    var currentAmpl = ampl?.current ?? 0.0;
    if ((currentAmpl) > minVolume) {
      setState(() {
        volume = ((currentAmpl) - minVolume) / minVolume;
      });
      //print('volume: $volume');
    }
  }

  int volume0to(int maxVolumeToDisplay) {
    return (volume * maxVolumeToDisplay).round().abs();
  }

  @override
  Status get currentState => _currentState;
}

Future<String> _getPath() async {
  final dir = await getApplicationDocumentsDirectory();
  var result = p.join(
    dir.path,
    'audio_${DateTime.now().millisecondsSinceEpoch}.wav',
  );

  return result;
}

enum Status {
  peak,
  silence,
}
