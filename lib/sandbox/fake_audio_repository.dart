/// Fake audio repository for sandbox / testing.
///
/// Implements [IAudioRepository] with pure no-ops — no microphone,
/// no speaker, no platform channel calls. All operations succeed immediately.
library fake_audio_repository;

import 'package:vocky_call/core/result/result.dart';
import 'package:vocky_call/domain/repositories/i_audio_repository.dart';
import 'package:vocky_call/domain/value_objects/audio_output_mode.dart';

final class FakeAudioRepository implements IAudioRepository {
  AudioOutputMode _mode = AudioOutputMode.loudspeaker;
  bool _muted = false;
  bool _capturing = false;
  bool _playing = false;

  @override
  AudioOutputMode get currentOutputMode => _mode;

  bool get isMuted => _muted;
  bool get isCapturing => _capturing;
  bool get isPlaying => _playing;

  @override
  Future<Result<void>> startCapture() async {
    _capturing = true;
    return Result.success(null);
  }

  @override
  Future<Result<void>> startPlayback() async {
    _playing = true;
    return Result.success(null);
  }

  @override
  Future<void> stop() async {
    _capturing = false;
    _playing = false;
  }

  @override
  Future<Result<void>> setOutputMode(AudioOutputMode mode) async {
    _mode = mode;
    return Result.success(null);
  }

  @override
  Future<Result<void>> setMuted({required bool muted}) async {
    _muted = muted;
    return Result.success(null);
  }
}
