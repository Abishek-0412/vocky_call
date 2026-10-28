/// Use case: accept an incoming call.
library accept_call_use_case;

import 'package:vocky_call/core/result/result.dart';
import 'package:vocky_call/domain/entities/call_session.dart';
import 'package:vocky_call/domain/repositories/i_transport_repository.dart';
import 'package:vocky_call/domain/repositories/i_audio_repository.dart';

final class AcceptCallUseCase {
  final ITransportRepository _transport;
  final IAudioRepository _audio;

  const AcceptCallUseCase(this._transport, this._audio);

  Future<Result<CallSession>> call(String callerId) async {
    final sessionResult = await _transport.acceptCall(callerId);
    if (sessionResult.isFailure) return Result.failure(sessionResult.failure);

    final captureResult = await _audio.startCapture();
    if (captureResult.isFailure) return Result.failure(captureResult.failure);

    final playbackResult = await _audio.startPlayback();
    if (playbackResult.isFailure) return Result.failure(playbackResult.failure);

    return sessionResult;
  }
}
