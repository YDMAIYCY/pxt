import 'package:path_provider/path_provider.dart';

import 'native_voice_backends.dart';
import 'offline_interview_voice_service.dart';
import 'offline_model_manager.dart';
import 'sherpa_streaming_asr.dart';
import 'voice_backends.dart';

export '../interview_voice_port.dart'
    show InterviewVoicePort, VoicePhase, VoiceTranscript;
export 'offline_interview_voice_service.dart';
export 'offline_model_manager.dart';
export 'voice_backends.dart';

/// Local inspection only; model downloads require an explicit ensureOfflineModel.
Future<OfflineInterviewVoiceService> createOfflineInterviewVoiceService({
  VoiceSettings settings = const VoiceSettings(),
}) async {
  final models = OfflineModelManager(
    documentsDirectory: await getApplicationDocumentsDirectory(),
  );
  await models.inspect();
  return OfflineInterviewVoiceService(
    modelManager: models,
    recorder: RecordVoiceRecorder(),
    asr: SherpaStreamingAsr(),
    speaker: LocalChineseVoiceSpeaker(),
    playback: SavedRecordingPlayback(),
    settings: settings,
  );
}
