/// Use case: make this device discoverable over Bluetooth.
library make_bt_discoverable_use_case;

import 'package:vocky_call/core/result/result.dart';
import 'package:vocky_call/domain/repositories/i_discovery_repository.dart';

final class MakeBtDiscoverableUseCase {
  final IDiscoveryRepository _repository;
  const MakeBtDiscoverableUseCase(this._repository);

  Future<Result<void>> call({int durationSeconds = 120}) =>
      _repository.makeDiscoverable(durationSeconds: durationSeconds);
}
