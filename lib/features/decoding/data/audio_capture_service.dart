import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException, PlatformException;
import 'package:record/record.dart';
import 'package:simply_morse/features/decoding/domain/services/audio_capture.dart';

/// Android recording source for the capture path — a diagnostic A/B
/// knob for the AGC pumping observed in the 2026-09-10 4 m captures
/// (mark level oscillating ±10 dB; the receiving phone's audio chain
/// re-riding gain while the tone plays).
///
/// - defaultSource: AudioSource.DEFAULT. OEM processing chains
///   (Samsung/Xiaomi-style DSP) may apply gain riding on any source.
/// - unprocessed: AudioSource.UNPROCESSED (API 24+). Requests the
///   raw mic with all effects bypassed where the device supports it
///   (PROPERTY_SUPPORT_AUDIO_UNPROCESSED); the record package falls
///   back to DEFAULT below API 24. The device's support flag is
///   logged in the capture `start` row.
/// - voiceRecognition: AudioSource.VOICE_RECOGNITION. The Android
///   CDD requires clean (AGC-free) input for this source on most
///   devices.
///
/// Change this constant and rebuild to run the A/B round. iOS and
/// web ignore it (iOS voice processing is already disabled via the
/// autoGain/echoCancel/noiseSuppress flags below).
const AndroidAudioSource kAndroidAudioSource = AndroidAudioSource.defaultSource;

/// Platform implementation of [AudioCapture] using the
/// `record` package.
///
/// Captures mono 16-bit PCM audio from the microphone at
/// 8 kHz sample rate, normalized to [-1, 1] doubles.
class AudioCaptureImpl implements AudioCapture {
  AudioCaptureImpl({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  /// Native query for whether this device delivers raw mic audio
  /// via AudioSource.UNPROCESSED. Implemented by the platform
  /// channel in MainActivity (Android only); any failure means
  /// unknown (null).
  static const MethodChannel _platformChannel = MethodChannel(
    'simplymorse/platform',
  );

  static Future<bool?> queryUnprocessedSupport() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await _platformChannel.invokeMethod<bool>(
        'getUnprocessedSupport',
      );
    } on MissingPluginException {
      return null; // channel absent (web/desktop unit tests)
    } on PlatformException {
      return null; // native side refused the query
    }
  }

  /// Builds the capture `start` row detail. Pure and testable: the
  /// active source and the UNPROCESSED support flag must be visible
  /// in every CSV so A/B rounds are self-describing.
  static String startDetail({
    required TargetPlatform platform,
    required AndroidAudioSource audioSource,
    bool? unprocessedSupported,
  }) {
    final fields = <String>[
      'requested_sample_rate=44100',
      'channels=1',
      'pcm16',
    ];
    if (platform == TargetPlatform.android) {
      fields.add('audio_source=${audioSource.name}');
      if (audioSource == AndroidAudioSource.unprocessed) {
        final flag = switch (unprocessedSupported) {
          true => '1',
          false => '0',
          _ => '?',
        };
        fields.add('unprocessed_supported=$flag');
      }
    } else if (platform == TargetPlatform.iOS) {
      // Voice processing (AGC) is disabled via the RecordConfig
      // flags; stated for self-documenting captures.
      fields.add('voice_agc=off');
    }
    return fields.join(' ');
  }

  final AudioRecorder _recorder;
  bool _isActive = false;

  @override
  DebugAudioCaptureEventCallback? onDebugEvent;

  int _wallMs() => DateTime.now().millisecondsSinceEpoch;

  @override
  bool get isActive => _isActive;

  @override
  Future<bool> hasPermission() async {
    final granted = await _recorder.hasPermission();
    onDebugEvent?.call(
      timestampMs: _wallMs(),
      event: 'permission',
      detail: 'granted=${granted ? 1 : 0}',
    );
    return granted;
  }

  @override
  Stream<List<double>> start() async* {
    _isActive = true;
    final wallStart = _wallMs();
    final unprocessedSupported =
        kAndroidAudioSource == AndroidAudioSource.unprocessed
        ? await queryUnprocessedSupport()
        : null;
    onDebugEvent?.call(
      timestampMs: wallStart,
      event: 'start',
      detail: startDetail(
        platform: defaultTargetPlatform,
        audioSource: kAndroidAudioSource,
        unprocessedSupported: unprocessedSupported,
      ),
    );

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 44100,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
        androidConfig: AndroidRecordConfig(
          audioSource: kAndroidAudioSource,
        ),
      ),
    );
    onDebugEvent?.call(
      timestampMs: _wallMs(),
      event: 'started',
      dtMs: _wallMs() - wallStart,
    );

    var bufferCount = 0;
    var lastBufferMs = _wallMs();
    await for (final data in stream) {
      if (!_isActive) break;
      final now = _wallMs();
      bufferCount++;
      onDebugEvent?.call(
        timestampMs: now,
        event: 'buffer',
        dtMs: now - lastBufferMs,
        detail: 'n=$bufferCount bytes=${data.length}',
      );
      lastBufferMs = now;
      yield _bytesToSamples(data);
    }
    _isActive = false;
  }

  @override
  Future<void> stop() async {
    if (!_isActive) return;
    _isActive = false;
    onDebugEvent?.call(timestampMs: _wallMs(), event: 'stop');
    try {
      await _recorder.stop();
    } on Object {
      // Recorder already stopped or the platform threw while
      // tearing down — the stream is closed either way, which
      // wakes the sample generator's await-for loop.
    }
  }

  /// Converts little-endian 16-bit signed PCM bytes to
  /// normalized doubles in [-1, 1].
  List<double> _bytesToSamples(Uint8List data) {
    final samples = <double>[];
    for (var i = 0; i + 1 < data.length; i += 2) {
      final raw = data[i] | (data[i + 1] << 8);
      final signed = raw > 32767 ? raw - 65536 : raw;
      samples.add(signed / 32768);
    }
    return samples;
  }
}
