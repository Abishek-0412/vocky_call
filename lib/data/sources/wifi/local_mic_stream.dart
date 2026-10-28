/// Single shared microphone stream for WiFi (WebRTC) calls.
///
/// The WebRTC transport adds this stream's track to the peer connection and
/// the audio repository mutes it, so both must use the same instance.
library local_mic_stream;

import 'package:flutter_webrtc/flutter_webrtc.dart';

class LocalMicStream {
  LocalMicStream._();

  static Future<MediaStream>? _stream;
  static bool _muted = false;

  static const _constraints = {
    'audio': {
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
    },
    'video': false,
  };

  static Future<MediaStream> get() {
    return _stream ??= navigator.mediaDevices
        .getUserMedia(_constraints)
        .then((s) {
      for (final t in s.getAudioTracks()) {
        t.enabled = !_muted;
      }
      return s;
    }).catchError((Object e) {
      _stream = null;
      throw e;
    });
  }

  static Future<void> setMuted(bool muted) async {
    _muted = muted;
    final s = await _stream;
    s?.getAudioTracks().forEach((t) => t.enabled = !muted);
  }

  static Future<void> release() async {
    final pending = _stream;
    _stream = null;
    _muted = false;
    if (pending == null) return;
    try {
      final s = await pending;
      for (final t in s.getTracks()) {
        await t.stop();
      }
      await s.dispose();
    } catch (_) {}
  }
}
