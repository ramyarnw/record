// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pcmtowave/convertToWav.dart';
import 'package:record/record.dart';
import 'package:record_audio/recorder.dart';

mixin AudioRecorderMixin {
  Future<void> recordFile(AudioRecorder recorder, RecordConfig config) async {
    final path = await _getPath();

    await recorder.start(config, path: path);
  }

  bool isProcessing = false;

  Status get currentState;

  List<Uint8List> wholeDataList = [];
  List<Uint8List> listData = [];
  Map<int, List<Uint8List>> mapData = {};

  final StreamController<List<Uint8List>> processController =
      StreamController<List<Uint8List>>.broadcast();

  Stream<List<Uint8List>> get processStream => processController.stream;
  StreamSubscription<RecordState>? _recordAddSub;

  Future<void> recordStream(AudioRecorder recorder, RecordConfig config) async {
    //move to listener
    //final path = await _getPath();

    //move to listener
    //final file = File(path);

    final stream = await recorder.startStream(config);

    // final _pcmtowave = convertToWav(
    //     sampleRate: 44100,
    //     converMiliSeconds: 100, //convert every 1 sec
    //     numChannels: 2);

    stream.listen(
      (data) async {
        // _pcmtowave.run(data);
        // for (var d in data) {
        // print(
        //   recorder.convertBytesToInt16(Uint8List.fromList(data)),
        // );
        print('currentState: $currentState');
        if (currentState == Status.peak) {
          listData.add(data);
        }

        if (currentState == Status.silence) {
          if ((listData.isNotEmpty) && (!isProcessing)) {
            isProcessing = true;
            int index = mapData.keys.length;
            mapData[index] = listData;
            processController.add(listData);
          }
        }

        //move to listener
        //file.writeAsBytesSync(data, mode: FileMode.append);
      },
      onDone: () {
        //print('End of stream. File written to $path.');
      },
    );
    //
    // _pcmtowave.convert.listen((data) async {
    //   file.writeAsBytesSync(data, mode: FileMode.append);
    // }
    // );
  }

  Future<String> _getPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(
      dir.path,
      'audio_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
  }
}
