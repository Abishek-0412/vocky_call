/// Bluetooth discovery data source.
///
/// Uses flutter_bluetooth_serial to scan for discoverable VockyCall devices.
///
/// A scan only finds phones that are discoverable, so on its own discovery
/// is one-way. After each scan we say hello ("announce") to the VockyCall
/// phones we know about, so they list us too even if we are not
/// discoverable. Hellos we receive add the sender to our list.
library bt_discovery_source;

import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:vocky_call/core/constants/app_constants.dart';
import 'package:vocky_call/core/errors/exceptions.dart';
import 'package:vocky_call/domain/entities/peer_device.dart';
import 'package:vocky_call/domain/value_objects/transport_type.dart';

import 'package:vocky_call/data/sources/i_discovery_source.dart';

abstract interface class IBtDiscoverySource implements IDiscoverySource {
  Future<void> makeDiscoverable({int durationSeconds = 120});
}

final class BtDiscoverySource implements IBtDiscoverySource {
  static const _btCall = MethodChannel(AppConstants.btCallChannel);
  static const _presence = EventChannel(AppConstants.btPresenceEventsChannel);

  /// Don't say hello to the same phone more often than this.
  static const _announceEvery = Duration(seconds: 30);

  final _controller = StreamController<PeerDevice>.broadcast();
  StreamSubscription<BluetoothDiscoveryResult>? _scanSubscription;
  StreamSubscription<dynamic>? _presenceSub;
  bool _isDisposed = false;

  /// Bumped on every start/stop so an old scan loop stops itself.
  int _generation = 0;
  String _localName = '';

  /// VockyCall phones we exchanged a hello with (address → name).
  /// Kept across refreshes so they come back after one scan cycle.
  final Map<String, String> _vockyPeers = {};
  final Map<String, DateTime> _lastAnnounce = {};

  /// When each phone last said hello to us. It already lists us, so we
  /// don't say hello back (two phones connecting to each other at the same
  /// time can stall the Bluetooth link).
  final Map<String, DateTime> _heardFrom = {};
  final _random = Random();

  @override
  TransportType get transportType => TransportType.bluetooth;

  @override
  Stream<PeerDevice> get peerStream => _controller.stream;

  @override
  Future<void> startDiscovery(String localDeviceName) async {
    final enabled = await FlutterBluetoothSerial.instance.isEnabled ?? false;
    if (!enabled) throw const TransportException('Bluetooth is off.');
    _localName = localDeviceName;
    _lastAnnounce.clear(); // after a refresh, say hello to everyone again
    _presenceSub ??= _presence.receiveBroadcastStream().listen(_onPresence);
    _startScanLoop(++_generation);
  }

  void _onPresence(dynamic event) {
    final map = Map<String, dynamic>.from(event as Map);
    final address = map['address'] as String;
    final name = (map['name'] as String?) ?? '';
    _vockyPeers[address] = name.isEmpty ? 'VockyCall Device' : name;
    _heardFrom[address] = DateTime.now();
    _emit(address, _vockyPeers[address]!);
  }

  void _emit(String address, String name) {
    if (_isDisposed) return;
    _controller.add(PeerDevice(
      id: address,
      name: name,
      transportType: TransportType.bluetooth,
      lastSeen: DateTime.now(),
    ));
  }

  bool _isCurrent(int gen) => !_isDisposed && gen == _generation;

  void _restartLater(int gen, int seconds) {
    Future.delayed(Duration(seconds: seconds), () => _startScanLoop(gen));
  }

  Future<void> _startScanLoop(int gen) async {
    if (!_isCurrent(gen)) return;
    await _cancelScan(); // Cancel any existing scan

    // Don't scan during a call — it chokes the Bluetooth audio link.
    if (await _isInCall()) {
      _restartLater(gen, 5);
      return;
    }

    try {
      // 1. Fetch bonded (paired) devices so paired devices display immediately
      final bondedDevices =
          await FlutterBluetoothSerial.instance.getBondedDevices();
      for (final device in bondedDevices) {
        if (!_isCurrent(gen)) return;
        final address = device.address;
        if (address.isNotEmpty && await _isCallCapable(address)) {
          _emit(address, device.name ?? 'Paired BT Device');
        }
      }

      // 2. Perform active discovery scan for unbonded discoverable devices
      final found = <String, String>{};
      _scanSubscription = FlutterBluetoothSerial.instance
          .startDiscovery()
          .listen(
        (result) async {
          final device = result.device;
          final address = device.address;
          if (address.isEmpty || !await _isCallCapable(address)) return;
          if (!_isCurrent(gen)) return;
          found[address] = device.name ?? 'Discovered BT Device';
          _emit(address, found[address]!);
        },
        onError: (_) {
          if (_isCurrent(gen)) _restartLater(gen, 10);
        },
        onDone: () async {
          if (!_isCurrent(gen)) return;
          await _announceAll(found, gen);
          // Restart scan periodically so new devices are found
          if (_isCurrent(gen)) _restartLater(gen, 5);
        },
      );
    } catch (_) {
      if (_isCurrent(gen)) _restartLater(gen, 10);
    }
  }

  /// Say hello to phones found in this scan and to known VockyCall phones.
  /// A phone that answers runs VockyCall, so (re)add it to the list.
  Future<void> _announceAll(Map<String, String> found, int gen) async {
    final targets = {...found, ..._vockyPeers};
    for (final MapEntry(key: address, value: name) in targets.entries) {
      if (!_isCurrent(gen) || await _isInCall()) return;
      final last = _lastAnnounce[address];
      if (last != null && DateTime.now().difference(last) < _announceEvery) {
        continue;
      }
      final heard = _heardFrom[address];
      if (heard != null &&
          DateTime.now().difference(heard) < _announceEvery * 4) {
        continue; // it found us itself, so it already lists us
      }
      // Small random delay so two phones rarely start at the same moment.
      await Future.delayed(Duration(milliseconds: _random.nextInt(2000)));
      if (!_isCurrent(gen) || await _isInCall()) return;
      _lastAnnounce[address] = DateTime.now();
      bool ok;
      try {
        ok = await _btCall.invokeMethod<bool>(
                'announce', {'address': address, 'name': _localName}) ??
            false;
      } catch (_) {
        ok = false;
      }
      if (ok && _isCurrent(gen)) {
        _vockyPeers[address] = _vockyPeers[address] ?? name;
        _emit(address, _vockyPeers[address]!);
      }
    }
  }

  Future<bool> _isInCall() async {
    try {
      return await _btCall.invokeMethod<bool>('isBusy') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Hides headphones, speakers, watches etc. — only phones/tablets can call.
  Future<bool> _isCallCapable(String address) async {
    try {
      return await _btCall.invokeMethod<bool>(
              'isCallCapable', {'address': address}) ??
          true;
    } catch (_) {
      return true;
    }
  }

  Future<void> _cancelScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await FlutterBluetoothSerial.instance.cancelDiscovery();
  }

  @override
  Future<void> stopDiscovery() async {
    _generation++;
    await _cancelScan();
  }

  @override
  Future<void> makeDiscoverable({int durationSeconds = 120}) async {
    // Returns the granted seconds, or -1 if the user tapped Deny.
    final granted = await FlutterBluetoothSerial.instance
        .requestDiscoverable(durationSeconds);
    if (granted == null || granted <= 0) {
      throw const TransportException('Bluetooth visibility was not allowed.');
    }
  }

  void dispose() {
    _isDisposed = true;
    stopDiscovery();
    _presenceSub?.cancel();
    _controller.close();
  }
}
