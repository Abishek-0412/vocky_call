/// Use case: change audio output routing during an active call.
library set_audio_output_use_case;

import 'package:vocky_call/core/result/result.dart';
import 'package:vocky_call/domain/repositories/i_audio_repository.dart';
import 'package:vocky_call/domain/value_objects/audio_output_mode.dart';

final class SetAudioOutputUseCase {
  final IAudioRepository _audio;
  const SetAudioOutputUseCase(this._audio);

  Future<Result<void>> call(AudioOutputMode mode) =>
      _audio.setOutputMode(mode);
}
