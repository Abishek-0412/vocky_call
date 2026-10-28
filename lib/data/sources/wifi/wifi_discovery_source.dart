/// WiFi discovery data source.
///
/// Broadcasts this device's presence every few seconds via UDP multicast
/// (239.255.0.1:9999) and subnet broadcast (many routers drop multicast),
/// and listens for other VockyCall devices on the same WiFi network.
///
/// Many phones drop broadcast/multicast packets (power save, router
/// filtering), so discovery could work in one direction only. To fix that,
/// every phone we hear from also gets our beacon sent to it directly.
library wifi_discovery_source;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:vocky_call/core/constants/app_constants.dart';
import 'package:vocky_call/core/errors/exceptions.dart';
import 'package:vocky_call/domain/entities/peer_device.dart';
import 'package:vocky_call/domain/value_objects/transport_type.dart';
import 'package:vocky_call/core/utils/network_utils.dart';

import 'package:vocky_call/data/sources/i_discovery_source.dart';

abstract interface class IWifiDiscoverySource implements IDiscoverySource {}

final class WifiDiscoverySource implements IWifiDiscoverySource {
  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  final _controller = StreamController<PeerDevice>.broadcast();
  List<int>? _beacon;

  /// Phones we heard from recently (address → last beacon time).
  final Map<String, DateTime> _heardFrom = {};

  /// Random per-launch id so we can ignore our own beacons.
  final String _instanceId =
      Random().nextInt(1 << 32).toRadixString(16).padLeft(8, '0');

  /// Debug only: peers that can't be discovered by broadcast, e.g. another
  /// emulator. Format: "Name@host:port,Name2@host2:port2".
  static const _staticPeers = String.fromEnvironment('VOCKY_STATIC_PEERS');

  @override
  TransportType get transportType => TransportType.wifi;

  @override
  Stream<PeerDevice> get peerStream => _controller.stream;

  @override
  Future<void> startDiscovery(String localDeviceName) async {
    // Acquire multicast lock via platform channel (Android requirement)
    const channel = MethodChannel(AppConstants.multicastLockChannel);
    await channel.invokeMethod('acquireMulticastLock');

    final local = await NetworkUtils.getLocalInterface();
    if (local == null && _staticPeers.isEmpty) {
      throw const TransportException(
          'Not connected to WiFi. Connect both phones to the same WiFi or hotspot.');
    }
    final localIp = local?.$2.address ?? '';

    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      AppConstants.discoveryPort,
      reuseAddress: true,
    );
    try {
      _socket!.joinMulticast(
          InternetAddress(AppConstants.multicastGroup), local?.$1);
    } catch (_) {
      // Multicast not available — subnet broadcast still works.
    }
    _socket!.broadcastEnabled = true;
    _socket!.multicastLoopback = false;

    _socket!.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = _socket?.receive();
      if (datagram == null) return;
      try {
        final json =
            jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
        if (json['id'] == _instanceId) return; // our own beacon
        final from = datagram.address;
        final isNew = !_heardFrom.containsKey(from.address);
        _heardFrom[from.address] = DateTime.now();
        // Reply straight away so they see us even if our broadcasts are lost.
        if (isNew) _send(from);
        _controller.add(PeerDevice(
          id: json['ip'] as String? ?? datagram.address.address,
          name: json['name'] as String,
          transportType: TransportType.wifi,
          lastSeen: DateTime.now(),
        ));
      } catch (_) {
        // Malformed packet — ignore
      }
    });

    if (localIp.isNotEmpty) {
      _beacon = utf8.encode(
          jsonEncode({'name': localDeviceName, 'ip': localIp, 'id': _instanceId}));
    }

    void tick() {
      _broadcast(local?.$2);
      _emitStaticPeers();
    }

    _broadcastTimer = Timer.periodic(
      Duration(seconds: AppConstants.heartbeatIntervalSec),
      (_) => tick(),
    );
    tick();
  }

  @override
  Future<void> stopDiscovery() async {
    _broadcastTimer?.cancel();
    _socket?.close();
    _socket = null;
    _beacon = null;
    _heardFrom.clear();
    const channel = MethodChannel(AppConstants.multicastLockChannel);
    await channel.invokeMethod('releaseMulticastLock');
  }

  void _broadcast(InternetAddress? localAddr) {
    final cutoff = DateTime.now()
        .subtract(const Duration(seconds: AppConstants.peerTimeoutSec));
    _heardFrom.removeWhere((_, seen) => seen.isBefore(cutoff));
    final targets = [
      InternetAddress(AppConstants.multicastGroup),
      InternetAddress('255.255.255.255'),
      if (localAddr != null) _subnetBroadcast(localAddr),
      for (final address in _heardFrom.keys) InternetAddress(address),
    ];
    targets.forEach(_send);
  }

  void _send(InternetAddress target) {
    final socket = _socket;
    final beacon = _beacon;
    if (socket == null || beacon == null) return;
    try {
      socket.send(beacon, target, AppConstants.discoveryPort);
    } catch (_) {}
  }

  /// Assumes a /24 network, which is what home routers and hotspots use.
  InternetAddress _subnetBroadcast(InternetAddress a) {
    final b = a.rawAddress;
    return InternetAddress('${b[0]}.${b[1]}.${b[2]}.255');
  }

  void _emitStaticPeers() {
    if (_staticPeers.isEmpty) return;
    for (final entry in _staticPeers.split(',')) {
      final parts = entry.split('@');
      if (parts.length != 2) continue;
      _controller.add(PeerDevice(
        id: parts[1].trim(),
        name: parts[0].trim(),
        transportType: TransportType.wifi,
        lastSeen: DateTime.now(),
      ));
    }
  }

  void dispose() {
    stopDiscovery();
    _controller.close();
  }
}
