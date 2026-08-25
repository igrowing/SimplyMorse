import 'package:get_it/get_it.dart';
import 'package:simply_morse/core/services/torch_service.dart';
import 'package:simply_morse/features/decoding/domain/services/morse_decoder.dart';
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
Future<void> configureDependencies() async {
  final getIt = GetIt.instance;

  final dataSource = LocalStorageDatasource();
  await dataSource.init();

  getIt
    ..registerSingleton<TorchService>(createTorchService())
    ..registerSingleton<LocalStorageDatasource>(dataSource)
    ..registerSingleton<SettingsRepository>(
      SettingsRepositoryImpl(dataSource),
    )
    ..registerSingleton<TextHistoryRepository>(
      TextHistoryRepositoryImpl(dataSource),
    )
    ..registerSingleton<MorseEncoder>(MorseEncoder())
    ..registerSingleton<MorseDecoder>(MorseDecoder())
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
    ..registerFactory<DecodingController>(
      () => DecodingController(
        morseDecoder: getIt<MorseDecoder>(),
      ),
    );
}
