/// Tests the call protocol in TransportRepositoryImpl:
/// invite → ring → accept → startMedia on both sides, plus decline / busy.
library transport_repository_test;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocky_call/core/constants/app_constants.dart';
import 'package:vocky_call/data/repositories/transport_repository_impl.dart';
import 'package:vocky_call/data/sources/i_transport_source.dart';
import 'package:vocky_call/domain/entities/peer_device.dart';
import 'package:vocky_call/domain/repositories/i_transport_repository.dart';
import 'package:vocky_call/domain/value_objects/transport_type.dart';

class _FakeSource implements ITransportSource {
  final signals = StreamController<Map<String, dynamic>>.broadcast();
  final sent = <Map<String, dynamic>>[];
  final mediaStarts = <(String, bool)>[];
  int closeCount = 0;

  @override
  TransportType get transportType => TransportType.wifi;
  @override
  Stream<Uint8List> get audioStream => const Stream.empty();
  @override
  Stream<Map<String, dynamic>> get signalingStream => signals.stream;
  @override
  Future<void> initialize(String localDeviceName) async {}
  @override
  Future<void> connectToPeer(String peerId, String localName) async {}
  @override
  Future<void> startMedia(String peerId, {required bool isCaller}) async =>
      mediaStarts.add((peerId, isCaller));
  @override
  Future<void> sendSignal(String peerId, Map<String, dynamic> message) async =>
      sent.add(message);
  @override
  Future<void> sendAudio(Uint8List chunk) async {}
  @override
  Future<void> closeAll() async => closeCount++;
  @override
  void dispose() {}
}

void main() {
  late _FakeSource source;
  late TransportRepositoryImpl repo;
  late List<SignalingEvent> events;

  setUp(() async {
    source = _FakeSource();
    repo = TransportRepositoryImpl(sources: [source], localDeviceName: 'Me');
    await repo.initializeSources();
    events = [];
    repo.signalingEvents.listen(events.add);
  });

  Future<void> receive(Map<String, dynamic> msg) async {
    source.signals.add(msg);
    await Future<void>.delayed(Duration.zero);
  }

  final peer = PeerDevice(
    id: '192.168.1.20',
    name: 'Phone B',
    transportType: TransportType.wifi,
    lastSeen: DateTime(2026),
  );

  test('caller sends invite and starts media only after accept', () async {
    final result = await repo.initiateCall([peer]);
    expect(result.isSuccess, isTrue);
    expect(source.sent.single['type'], AppConstants.sigCallInvite);
    expect(source.mediaStarts, isEmpty);

    await receive({'type': AppConstants.sigCallAccept, 'fromIp': peer.id});
    expect(source.mediaStarts, [(peer.id, true)]);
    expect(events.single, isA<CallConnectedEvent>());
  });

  test('sessions carry participant display names', () async {
    final caller = await repo.initiateCall([peer]);
    expect(caller.value.participantNames, {peer.id: 'Phone B'});
  });

  test('callee rings, then accepting sends accept and starts media', () async {
    await receive({
      'type': AppConstants.sigCallInvite,
      'from': 'Phone A',
      'fromIp': '192.168.1.10',
    });
    final ring = events.single as IncomingCallEvent;
    expect(ring.callerName, 'Phone A');

    final result = await repo.acceptCall(ring.callerId);
    expect(result.isSuccess, isTrue);
    expect(source.sent.single['type'], AppConstants.sigCallAccept);
    expect(source.mediaStarts, [('192.168.1.10', false)]);
  });

  test('caller is told when the callee declines', () async {
    await repo.initiateCall([peer]);
    await receive({'type': AppConstants.sigCallDecline, 'fromIp': peer.id});

    final ended = events.single as CallEndedEvent;
    expect(ended.reason, 'declined');
    expect(source.closeCount, 1);
  });

  test('a second invite during a call is answered with busy', () async {
    await repo.initiateCall([peer]);
    source.sent.clear();
    await receive({
      'type': AppConstants.sigCallInvite,
      'from': 'Phone C',
      'fromIp': '192.168.1.30',
    });
    expect(events, isEmpty);
    expect(source.sent.single['type'], AppConstants.sigCallDecline);
    expect(source.sent.single['reason'], 'busy');
  });
}
