/// Bluetooth transport source — RFCOMM socket for signaling and PCM audio.
///
/// The socket, the listening server and the audio loop (8 kHz / 16-bit /
/// mono PCM) live in native code (BtCallService.kt), so audio never has to
/// cross the platform channel. This class only forwards signaling.
library bt_transport_source;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:vocky_call/core/constants/app_constants.dart';

import 'package:vocky_call/core/errors/exceptions.dart';
import 'package:vocky_call/data/sources/i_transport_source.dart';
import 'package:vocky_call/domain/value_objects/transport_type.dart';

abstract interface class IBtTransportSource implements ITransportSource {
  Future<void> listenForIncoming();
}

final class BtTransportSource implements IBtTransportSource {
  static const _channel = MethodChannel(AppConstants.btCallChannel);
  static const _events = EventChannel(AppConstants.btCallEventsChannel);

  final _audioController = StreamController<Uint8List>.broadcast();
  final _signalingController =
      StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription<dynamic>? _eventSub;

  @override
  TransportType get transportType => TransportType.bluetooth;

  /// Audio is played natively; this stream stays empty.
  @override
  Stream<Uint8List> get audioStream => _audioController.stream;

  @override
  Stream<Map<String, dynamic>> get signalingStream =>
      _signalingController.stream;

  @override
  Future<void> initialize(String localDeviceName) async {
    _eventSub ??= _events.receiveBroadcastStream().listen(_onNativeEvent);
    await listenForIncoming();
  }

  @override
  Future<void> listenForIncoming() async {
    await _channel.invokeMethod('listen');
  }

  @override
  Future<void> connectToPeer(String peerId, String localName) async {
    try {
      await _channel.invokeMethod('connect', {'address': peerId});
    } on PlatformException catch (e) {
      throw TransportException(
        'Could not connect to Bluetooth device ($peerId). Make sure VockyCall '
        'is open on the other phone and Bluetooth is on. (${e.message})',
      );
    }
  }

  @override
  Future<void> startMedia(String peerId, {required bool isCaller}) async {
    await _channel.invokeMethod('startAudio');
  }

  @override
  Future<void> sendSignal(String peerId, Map<String, dynamic> message) async {
    await _channel.invokeMethod('sendSignal', {'json': jsonEncode(message)});
  }

  @override
  Future<void> sendAudio(Uint8List pcmChunk) async {
    // Audio is captured and sent natively.
  }

  @override
  Future<void> closeAll() async {
    await _channel.invokeMethod('hangup');
  }

  // ── Private ──────────────────────────────────────────────────────────────

  void _onNativeEvent(dynamic event) {
    final map = Map<String, dynamic>.from(event as Map);
    final address = map['address'] as String?;
    switch (map['event']) {
      case 'signal':
        try {
          final msg = jsonDecode(map['json'] as String) as Map<String, dynamic>;
          _signalingController.add(msg..['fromIp'] = address);
        } catch (_) {}
      case 'disconnected':
        _signalingController.add({
          'type': AppConstants.sigCallEnd,
          'fromIp': address,
          'reason': 'connection_closed',
        });
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    closeAll();
    _audioController.close();
    _signalingController.close();
  }
}
