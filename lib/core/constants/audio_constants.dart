/// Audio configuration constants.
/// All audio format decisions are centralised here.
library audio_constants;

import 'package:vocky_call/core/constants/app_constants.dart';

class AudioConstants {
  AudioConstants._();

  // ── WiFi Mode (WebRTC / Opus) ─────────────────────────────────
  /// WebRTC uses Opus by default at 48 kHz internally.
  /// No explicit PCM config needed — WebRTC handles it.

  // ── Bluetooth Mode (Raw PCM over RFCOMM) ─────────────────────
  /// 8 kHz mono 16-bit = 128 kbps — fits comfortably in BT bandwidth.
  static const int btSampleRate = 8000;
  static const int btChannelCount = 1; // mono
  static const int btBitDepth = 16;

  /// Buffer size in frames (10 ms chunks at 8 kHz = 80 samples).
  static const int btFrameSize = 80;

  /// Bytes per frame: 80 samples × 2 bytes (16-bit) = 160 bytes.
  static const int btFrameBytes = btFrameSize * 2;

  // ── Platform Channel Names (delegates to AppConstants) ────────
  static const String audioRoutingChannel = AppConstants.audioRoutingChannel;
  static const String multicastLockChannel = AppConstants.multicastLockChannel;

  // ── Platform Channel Methods ──────────────────────────────────
  static const String methodSetEarpiece = 'setEarpiece';
  static const String methodSetSpeaker = 'setSpeaker';
  static const String methodAcquireMulticastLock = 'acquireMulticastLock';
  static const String methodReleaseMulticastLock = 'releaseMulticastLock';
}
