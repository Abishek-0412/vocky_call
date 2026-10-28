/// Audio repository interface.
///
/// Abstracts audio capture, playback, and output routing.
library i_audio_repository;

import 'package:vocky_call/core/result/result.dart';
import 'package:vocky_call/domain/value_objects/audio_output_mode.dart';

abstract interface class IAudioRepository {
  /// Begin capturing microphone audio. Emits raw PCM chunks.
  Future<Result<void>> startCapture();

  /// Begin playing back audio received from remote peers.
  Future<Result<void>> startPlayback();

  /// Stop all audio activity and release hardware resources.
  Future<void> stop();

  /// Route audio output to the given mode (earpiece / speaker / walkie).
  Future<Result<void>> setOutputMode(AudioOutputMode mode);

  /// Mute or unmute the microphone.
  Future<Result<void>> setMuted({required bool muted});

  /// Current output mode.
  AudioOutputMode get currentOutputMode;
}
