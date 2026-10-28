/// Immutable AudioSettings entity — holds user's audio preferences during a call.
library audio_settings;

import 'package:vocky_call/domain/value_objects/audio_output_mode.dart';

final class AudioSettings {
  final AudioOutputMode outputMode;
  final bool isMuted;
  final bool isPttPressed; // Push-to-talk active (walkie-talkie mode only)

  const AudioSettings({
    this.outputMode = AudioOutputMode.loudspeaker,
    this.isMuted = false,
    this.isPttPressed = false,
  });

  AudioSettings copyWith({
    AudioOutputMode? outputMode,
    bool? isMuted,
    bool? isPttPressed,
  }) {
    return AudioSettings(
      outputMode: outputMode ?? this.outputMode,
      isMuted: isMuted ?? this.isMuted,
      isPttPressed: isPttPressed ?? this.isPttPressed,
    );
  }

  /// In walkie-talkie mode, mic is active only while PTT is pressed.
  bool get isMicActive {
    if (outputMode == AudioOutputMode.walkieTalkie) return isPttPressed;
    return !isMuted;
  }
}
