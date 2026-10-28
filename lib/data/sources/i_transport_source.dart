import 'dart:async';
import 'dart:typed_data';
import 'package:vocky_call/domain/value_objects/transport_type.dart';

abstract interface class ITransportSource {
  TransportType get transportType;
  Stream<Uint8List> get audioStream;
  Stream<Map<String, dynamic>> get signalingStream;

  /// Start listening for incoming connections (e.g. TCP server, BT RFCOMM).
  Future<void> initialize(String localDeviceName);

  /// Open a signaling channel to [peerId] (no audio yet).
  Future<void> connectToPeer(String peerId, String localName);

  /// Start two-way audio with [peerId]. Called on both sides once the call
  /// is accepted. [isCaller] decides who creates the WebRTC offer.
  Future<void> startMedia(String peerId, {required bool isCaller});

  Future<void> sendSignal(String peerId, Map<String, dynamic> message);
  Future<void> sendAudio(Uint8List chunk);

  /// Close the current call's connections. Keeps listening for new calls.
  Future<void> closeAll();
  void dispose();
}
