/// Use case: toggle microphone mute state.
library toggle_mute_use_case;

import 'package:vocky_call/core/result/result.dart';
import 'package:vocky_call/domain/repositories/i_audio_repository.dart';

final class ToggleMuteUseCase {
  final IAudioRepository _audio;
  const ToggleMuteUseCase(this._audio);

  Future<Result<void>> call({required bool muted}) =>
      _audio.setMuted(muted: muted);
}
