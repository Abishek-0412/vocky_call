/// Tests for the fake WebRTC and BT transport sources.
///
/// Verifies that:
///   1. injectIncomingCall() fires a sigCallInvite on the signaling stream.
///   2. injectCallEnd() fires a sigCallEnd on the signaling stream.
///   3. connectToPeer() fires a sigCallAccept after the simulated delay.
///   4. closeAll() clears the active-call flag.
library fake_transport_source_test;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocky_call/core/constants/app_constants.dart';
import 'package:vocky_call/sandbox/fake_bt_transport_source.dart';
import 'package:vocky_call/sandbox/fake_webrtc_transport_source.dart';

void main() {
  group('FakeWebRtcTransportSource', () {
    late FakeWebRtcTransportSource transport;

    setUp(() => transport = FakeWebRtcTransportSource());
    tearDown(() => transport.dispose());

    test('injectIncomingCall emits sigCallInvite', () async {
      final signals = <Map<String, dynamic>>[];
      final sub = transport.signalingStream.listen(signals.add);

      transport.injectIncomingCall(
        callerId: '1.2.3.4',
        callerName: 'Test Caller',
      );
      await Future.delayed(const Duration(milliseconds: 50));

      expect(
        signals.any((s) => s['type'] == AppConstants.sigCallInvite),
        isTrue,
      );
      await sub.cancel();
    });

    test('injectIncomingCall sets isCallActive = true', () {
      expect(transport.isCallActive, isFalse);
      transport.injectIncomingCall();
      expect(transport.isCallActive, isTrue);
    });

    test('injectCallEnd emits sigCallEnd and clears isCallActive', () async {
      final signals = <Map<String, dynamic>>[];
      final sub = transport.signalingStream.listen(signals.add);

      transport.injectIncomingCall();
      transport.injectCallEnd();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(
        signals.any((s) => s['type'] == AppConstants.sigCallEnd),
        isTrue,
      );
      expect(transport.isCallActive, isFalse);
      await sub.cancel();
    });

    test('connectToPeer emits sigCallAccept after delay', () async {
      final signals = <Map<String, dynamic>>[];
      final sub = transport.signalingStream.listen(signals.add);

      await transport.connectToPeer('192.168.1.20', 'LocalDevice');
      // connectToPeer has a 1.5 s delay — wait for it.
      await Future.delayed(const Duration(milliseconds: 200));

      expect(
        signals.any((s) => s['type'] == AppConstants.sigCallAccept),
        isTrue,
      );
      await sub.cancel();
    });

    test('closeAll() sets isCallActive = false', () async {
      transport.injectIncomingCall();
      await transport.closeAll();
      expect(transport.isCallActive, isFalse);
    });
  });

  group('FakeBtTransportSource', () {
    late FakeBtTransportSource transport;

    setUp(() => transport = FakeBtTransportSource());
    tearDown(() => transport.dispose());

    test('injectIncomingCall emits sigCallInvite without fromIp key', () async {
      final signals = <Map<String, dynamic>>[];
      final sub = transport.signalingStream.listen(signals.add);

      transport.injectIncomingCall(callerName: 'BT Test Caller');
      await Future.delayed(const Duration(milliseconds: 50));

      final invite = signals.firstWhere(
        (s) => s['type'] == AppConstants.sigCallInvite,
        orElse: () => {},
      );
      expect(invite, isNotEmpty);
      // BT invite must NOT have a 'fromIp' key
      expect(invite.containsKey('fromIp'), isFalse);
      await sub.cancel();
    });

    test('injectCallEnd emits sigCallEnd', () async {
      final signals = <Map<String, dynamic>>[];
      final sub = transport.signalingStream.listen(signals.add);

      transport.injectIncomingCall();
      transport.injectCallEnd();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(
        signals.any((s) => s['type'] == AppConstants.sigCallEnd),
        isTrue,
      );
      await sub.cancel();
    });

    test('closeAll() disconnects', () async {
      transport.injectIncomingCall();
      expect(transport.isConnected, isTrue);
      await transport.closeAll();
      expect(transport.isConnected, isFalse);
    });

    test('sendAudio() completes without error', () async {
      await expectLater(
        transport.sendAudio(Uint8List(320)),
        completes,
      );
    });
  });
}
