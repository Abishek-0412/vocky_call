/// Use case: end the active call and release all resources.
library end_call_use_case;

import 'package:vocky_call/core/result/result.dart';
import 'package:vocky_call/domain/repositories/i_transport_repository.dart';
import 'package:vocky_call/domain/repositories/i_audio_repository.dart';

final class EndCallUseCase {
  final ITransportRepository _transport;
  final IAudioRepository _audio;

  const EndCallUseCase(this._transport, this._audio);

  Future<Result<void>> call(String sessionId) async {
    await _audio.stop();
    return _transport.endCall(sessionId);
  }
}
