/// Audio output routing mode.
library audio_output_mode;

enum AudioOutputMode {
  /// Routes audio to the earpiece (private, quiet — like a phone call held to ear).
  earpiece,

  /// Routes audio to the loudspeaker (hands-free).
  loudspeaker,

  /// Loudspeaker + mic muted until the user holds the Talk button (PTT).
  walkieTalkie;

  String get label => switch (this) {
        AudioOutputMode.earpiece => 'Earpiece',
        AudioOutputMode.loudspeaker => 'Speaker',
        AudioOutputMode.walkieTalkie => 'Walkie',
      };

  String get emoji => switch (this) {
        AudioOutputMode.earpiece => '🦻',
        AudioOutputMode.loudspeaker => '🔊',
        AudioOutputMode.walkieTalkie => '🎙',
      };
}
