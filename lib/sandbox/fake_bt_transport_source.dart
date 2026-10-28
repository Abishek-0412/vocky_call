/// Fake Bluetooth transport source for sandbox / testing.
///
/// Simulates RFCOMM call lifecycle using in-process streams.
/// No real BluetoothConnection or RFCOMM socket is opened.
/// Implements [IBtTransportSource].
library fake_bt_transport_source;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:vocky_call/core/constants/app_constants.dart';
import 'package:vocky_call/data/sources/bluetooth/bt_transport_source.dart';
import 'package:vocky_call/domain/value_objects/transport_type.dart';

final class FakeBtTransportSource implements IBtTransportSource {
  final _audioController = StreamController<Uint8List>.broadcast();
  final _signalingController =
      StreamController<Map<String, dynamic>>.broadcast();

  Timer? _audioLevelTimer;
  bool _connected = false;

  // Expose signaling controller so the sandbox control panel can inject events.
  StreamController<Map<String, dynamic>> get signalingInjector =>
      _signalingController;

  @override
  TransportType get transportType => TransportType.bluetooth;

  @override
  Stream<Uint8List> get audioStream => _audioController.stream;

  @override
  Stream<Map<String, dynamic>> get signalingStream =>
      _signalingController.stream;

  // ── IBtTransportSource implementation ─────────────────────────────────────

  @override
  Future<void> initialize(String localDeviceName) async {
    // No-op — incoming calls are injected via [injectIncomingCall].
  }

  @override
  Future<void> connectToPeer(String peerId, String localName) async {
    // Simulate BT pairing + RFCOMM connect delay.
    await Future.delayed(const Duration(milliseconds: 800));
    _connected = true;

    // Echo back an accept signal as if the remote device answered.
    await Future.delayed(const Duration(milliseconds: 700));
    _signalingController.add({
      'type': AppConstants.sigCallAccept,
      'from': 'Sandbox BT Device',
    });
    _startFakeAudio();
  }

  @override
  Future<void> startMedia(String peerId, {required bool isCaller}) async {}

  @override
  Future<void> listenForIncoming() async {
    // No-op — incoming calls are injected via [injectIncomingCall].
  }

  @override
  Future<void> sendSignal(String peerId, Map<String, dynamic> message) async {
    final type = message['type'];
    if (type == AppConstants.sigCallEnd ||
        type == AppConstants.sigCallDecline) {
      _stopFakeAudio();
      _connected = false;
    }
  }

  @override
  Future<void> sendAudio(Uint8List pcmChunk) async {
    // No-op — sandbox doesn't loop audio back.
  }

  @override
  Future<void> closeAll() async {
    _stopFakeAudio();
    _connected = false;
  }

  // ── Sandbox helpers (called by SandboxControlPanel) ───────────────────────

  /// Simulate an incoming BT call from a fake paired device.
  void injectIncomingCall({
    String callerId = 'AA:BB:CC:DD:EE:99',
    String callerName = 'Sandbox BT Remote',
  }) {
    _signalingController.add({
      'type': AppConstants.sigCallInvite,
      'from': callerName,
      // No 'fromIp' key — signals BT transport in TransportRepositoryImpl
      'sessionId': _generateId(),
    });
    _startFakeAudio();
    _connected = true;
  }

  /// Simulate the BT peer hanging up or disconnecting.
  void injectCallEnd() {
    _signalingController.add({
      'type': AppConstants.sigCallEnd,
      'reason': 'connection_closed',
    });
    _stopFakeAudio();
    _connected = false;
  }

  bool get isConnected => _connected;

  // ── Private ───────────────────────────────────────────────────────────────

  void _startFakeAudio() {
    _stopFakeAudio();
    final rng = Random();
    // Emit fake silent PCM chunks every 20 ms (mimics 8 kHz mono 16-bit chunks).
    _audioLevelTimer =
        Timer.periodic(const Duration(milliseconds: 20), (_) {
      // 160 samples × 2 bytes = 320-byte PCM chunk at 8 kHz
      final chunk = Uint8List(320);
      for (int i = 0; i < chunk.length; i++) {
        chunk[i] = rng.nextInt(10); // near-silence background noise
      }
      if (!_audioController.isClosed) _audioController.add(chunk);
    });
  }

  void _stopFakeAudio() {
    _audioLevelTimer?.cancel();
    _audioLevelTimer = null;
  }

  String _generateId() =>
      DateTime.now().millisecondsSinceEpoch.toRadixString(16) +
      Random().nextInt(9999).toString();

  void dispose() {
    closeAll();
    _audioController.close();
    _signalingController.close();
  }
}
