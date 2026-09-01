import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get_it/get_it.dart';
import 'package:simply_morse/core/services/feedback_service.dart';
import 'package:simply_morse/core/services/feedback_service_impl.dart';
import 'package:simply_morse/core/services/screen_flash_service.dart';
import 'package:simply_morse/core/services/screen_timeout_service.dart';
import 'package:simply_morse/core/services/share_service.dart';
import 'package:simply_morse/core/services/share_service_impl.dart';
import 'package:simply_morse/core/services/torch_service.dart';
import 'package:simply_morse/core/theme/theme_controller.dart';
import 'package:simply_morse/features/decoding/data/audio_capture_service.dart';
import 'package:simply_morse/features/decoding/data/audio_debug_logger.dart';
import 'package:simply_morse/features/decoding/data/camera_capture_service.dart';
import 'package:simply_morse/features/decoding/data/video_debug_logger.dart';
import 'package:simply_morse/features/decoding/domain/services/audio_capture.dart';
import 'package:simply_morse/features/decoding/domain/services/audio_decoder.dart';
import 'package:simply_morse/features/decoding/domain/services/camera_capture.dart';
import 'package:simply_morse/features/decoding/domain/services/morse_decoder.dart';
import 'package:simply_morse/features/decoding/domain/services/video_decoder.dart';
import 'package:simply_morse/features/decoding/presentation/controllers/decoding_controller.dart';
import 'package:simply_morse/features/encoding/data/datasources/local_storage_datasource.dart';
import 'package:simply_morse/features/encoding/data/repositories/settings_repository_impl.dart';
import 'package:simply_morse/features/encoding/data/repositories/text_history_repository_impl.dart';
import 'package:simply_morse/features/encoding/domain/repositories/settings_repository.dart';
import 'package:simply_morse/features/encoding/domain/repositories/text_history_repository.dart';
import 'package:simply_morse/features/encoding/domain/services/morse_encoder.dart';
import 'package:simply_morse/features/encoding/domain/services/morse_transmitter.dart';
import 'package:simply_morse/features/encoding/presentation/controllers/encoding_controller.dart';

/// Configures the service locator with all dependencies.
///
/// On web, [ScreenFlashService] is registered as the
/// [TorchService] implementation — it emulates the LED
/// using the screen instead of hardware torch.
Future<void> configureDependencies() async {
  final getIt = GetIt.instance;

  final dataSource = LocalStorageDatasource();
  await dataSource.init();

  final cameraCapture = CameraCaptureImpl();

  // Register the appropriate torch service for the platform.
  if (kIsWeb) {
    final screenFlash = ScreenFlashService();
    getIt
      ..registerSingleton<TorchService>(screenFlash)
      ..registerSingleton<ScreenFlashService>(screenFlash);
  } else {
    getIt.registerSingleton<TorchService>(createTorchService());
  }

  getIt
    ..registerSingleton<ShareService>(ShareServiceImpl())
    ..registerSingleton<FeedbackService>(FeedbackServiceImpl())
    ..registerSingleton<LocalStorageDatasource>(dataSource)
    ..registerSingleton<SettingsRepository>(
      SettingsRepositoryImpl(dataSource),
    )
    ..registerSingleton<TextHistoryRepository>(
      TextHistoryRepositoryImpl(dataSource),
    )
    ..registerSingleton<MorseEncoder>(MorseEncoder())
    ..registerSingleton<MorseDecoder>(MorseDecoder())
    ..registerSingleton<AudioCapture>(AudioCaptureImpl())
    ..registerSingleton<CameraCapture>(cameraCapture)
    ..registerSingleton<CameraCaptureImpl>(cameraCapture)
    ..registerSingleton<ThemeController>(ThemeController())
    ..registerSingleton<ScreenTimeoutService>(ScreenTimeoutService())
    ..registerFactory<MorseTransmitter>(
      () => MorseTransmitter(
        torchService: getIt<TorchService>(),
      ),
    )
    ..registerFactory<EncodingController>(
      () => EncodingController(
        settingsRepository: getIt<SettingsRepository>(),
        textHistoryRepository: getIt<TextHistoryRepository>(),
        morseEncoder: getIt<MorseEncoder>(),
        morseTransmitter: getIt<MorseTransmitter>(),
      ),
    )
    ..registerFactory<AudioDecoder>(
      () => AudioDecoder(
        sampleRate: 44100,
        fftSize: 2048,
        blockSize: 220,
      ),
    )
    ..registerSingleton<AudioDebugLogger>(AudioDebugLogger())
    ..registerSingleton<VideoDebugLogger>(VideoDebugLogger())
    ..registerFactory<VideoDecoder>(VideoDecoder.new)
    ..registerFactory<DecodingController>(
      () => DecodingController(
        morseDecoder: getIt<MorseDecoder>(),
        audioDecoder: getIt<AudioDecoder>(),
        debugLogger: getIt<AudioDebugLogger>(),
        videoDebugLogger: getIt<VideoDebugLogger>(),
        audioCapture: getIt<AudioCapture>(),
        videoDecoder: getIt<VideoDecoder>(),
        cameraCapture: getIt<CameraCapture>(),
      ),
    );
}
