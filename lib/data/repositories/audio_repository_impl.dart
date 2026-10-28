/// Audio repository implementation.
///
/// Delegates audio output routing to the native Android platform channel.
/// The microphone is opened by the transport when audio starts:
///   WiFi → shared WebRTC stream ([LocalMicStream]),
///   Bluetooth → native AudioRecord (BtCallService.kt).
/// This class only routes output and mutes whichever one is in use.
library audio_repository_impl;

import 'package:flutter/services.dart';
import 'package:vocky_call/core/constants/app_constants.dart';
import 'package:vocky_call/core/constants/audio_constants.dart';
import 'package:vocky_call/data/sources/wifi/local_mic_stream.dart';
import 'package:vocky_call/core/errors/failures.dart';
import 'package:vocky_call/core/result/result.dart';
import 'package:vocky_call/domain/repositories/i_audio_repository.dart';
import 'package:vocky_call/domain/value_objects/audio_output_mode.dart';

final class AudioRepositoryImpl implements IAudioRepository {
  static const _audioChannel = MethodChannel(AudioConstants.audioRoutingChannel);
  static const _btChannel = MethodChannel(AppConstants.btCallChannel);

  AudioOutputMode _currentMode = AudioOutputMode.loudspeaker;

  @override
  AudioOutputMode get currentOutputMode => _currentMode;

  @override
  Future<Result<void>> startCapture() async {
    // Opening a second capture here would steal the mic from the call.
    return Result.success(null);
  }

  @override
  Future<Result<void>> startPlayback() async {
    // WebRTC handles playback via RTCPeerConnection tracks automatically.
    // Default to loudspeaker for hands-free call experience.
    return setOutputMode(_currentMode);
  }

  @override
  Future<void> stop() async {
    await LocalMicStream.release();
    try {
      await _btChannel.invokeMethod('setMuted', {'muted': false});
    } catch (_) {}
  }

  @override
  Future<Result<void>> setOutputMode(AudioOutputMode mode) async {
    try {
      _currentMode = mode;
      switch (mode) {
        case AudioOutputMode.earpiece:
          await _audioChannel.invokeMethod(AudioConstants.methodSetEarpiece);
        case AudioOutputMode.loudspeaker:
        case AudioOutputMode.walkieTalkie:
          // Walkie-talkie uses speaker — PTT controls mic, not speaker
          await _audioChannel.invokeMethod(AudioConstants.methodSetSpeaker);
      }
      return Result.success(null);
    } on PlatformException catch (e) {
      return Result.failure(AudioFailure('Audio routing failed: ${e.message}'));
    }
  }

  @override
  Future<Result<void>> setMuted({required bool muted}) async {
    try {
      await LocalMicStream.setMuted(muted);
      await _btChannel.invokeMethod('setMuted', {'muted': muted});
      return Result.success(null);
    } catch (e) {
      return Result.failure(AudioFailure('Mute failed: $e'));
    }
  }
}
