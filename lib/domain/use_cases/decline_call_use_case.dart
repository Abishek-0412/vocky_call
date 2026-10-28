/// Use case: decline an incoming call.
library decline_call_use_case;

import 'package:vocky_call/core/result/result.dart';
import 'package:vocky_call/domain/repositories/i_transport_repository.dart';

final class DeclineCallUseCase {
  final ITransportRepository _transport;
  const DeclineCallUseCase(this._transport);

  Future<Result<void>> call(String callerId) =>
      _transport.declineCall(callerId);
}
