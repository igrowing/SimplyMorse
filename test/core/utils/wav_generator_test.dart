import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/core/utils/wav_generator.dart';

void main() {
  late WavGenerator generator;

  setUp(() {
    generator = WavGenerator(sampleRate: 8000);
  });

  group('WavGenerator.generate', () {
    test('produces valid RIFF header', () {
      final wav = generator.generate(
        [const ToneSegment(isOn: true, durationMs: 100)],
        700,
      );

      expect(wav[0], 0x52); // 'R'
      expect(wav[1], 0x49); // 'I'
      expect(wav[2], 0x46); // 'F'
      expect(wav[3], 0x46); // 'F'
    });

    test('produces valid WAVE format identifier', () {
      final wav = generator.generate(
        [const ToneSegment(isOn: true, durationMs: 100)],
        700,
      );

      expect(wav[8], 0x57); // 'W'
      expect(wav[9], 0x41); // 'A'
      expect(wav[10], 0x56); // 'V'
      expect(wav[11], 0x45); // 'E'
    });

    test('has correct fmt chunk', () {
      final wav = generator.generate(
        [const ToneSegment(isOn: true, durationMs: 100)],
        700,
      );

      // "fmt " marker at offset 12
      expect(wav[12], 0x66); // 'f'
      expect(wav[13], 0x6D); // 'm'
      expect(wav[14], 0x74); // 't'
      expect(wav[15], 0x20); // ' '

      // Audio format = 1 (PCM) at offset 20
      expect(wav[20], 1);
      expect(wav[21], 0);

      // Num channels = 1 (mono) at offset 22
      expect(wav[22], 1);
      expect(wav[23], 0);

      // Bits per sample = 16 at offset 34
      expect(wav[34], 16);
      expect(wav[35], 0);
    });

    test('has correct sample rate in header', () {
      final wav = generator.generate(
        [const ToneSegment(isOn: true, durationMs: 100)],
        700,
      );

      // Sample rate at offset 24 (little-endian)
      final sampleRate =
          wav[24] | (wav[25] << 8) | (wav[26] << 16) | (wav[27] << 24);
      expect(sampleRate, 8000);
    });

    test('has correct data chunk marker', () {
      final wav = generator.generate(
        [const ToneSegment(isOn: true, durationMs: 100)],
        700,
      );

      expect(wav[36], 0x64); // 'd'
      expect(wav[37], 0x61); // 'a'
      expect(wav[38], 0x74); // 't'
      expect(wav[39], 0x61); // 'a'
    });

    test('total size matches segment duration', () {
      const durationMs = 200;
      final wav = generator.generate(
        [const ToneSegment(isOn: true, durationMs: durationMs)],
        700,
      );

      // Expected samples: 200ms * 8000Hz / 1000 = 1600
      const expectedSamples = 1600;
      const expectedDataSize = expectedSamples * 2;
      const expectedFileSize = 44 + expectedDataSize;

      expect(wav.length, expectedFileSize);

      // Data size at offset 40 (little-endian)
      final dataSize =
          wav[40] | (wav[41] << 8) | (wav[42] << 16) | (wav[43] << 24);
      expect(dataSize, expectedDataSize);
    });

    test('tone segment produces non-zero samples', () {
      final wav = generator.generate(
        [const ToneSegment(isOn: true, durationMs: 100)],
        700,
      );

      // Check samples after the 44-byte header
      var hasNonZero = false;
      for (var i = 44; i < wav.length; i += 2) {
        final sample = wav[i] | (wav[i + 1] << 8);
        if (sample != 0) {
          hasNonZero = true;
          break;
        }
      }
      expect(hasNonZero, isTrue);
    });

    test('silence segment produces all-zero samples', () {
      final wav = generator.generate(
        [const ToneSegment(isOn: false, durationMs: 100)],
        700,
      );

      // All samples should be zero
      for (var i = 44; i < wav.length; i += 2) {
        final sample = wav[i] | (wav[i + 1] << 8);
        expect(sample, 0);
      }
    });

    test('multiple segments produce correct total size', () {
      final wav = generator.generate(
        [
          const ToneSegment(isOn: true, durationMs: 50),
          const ToneSegment(isOn: false, durationMs: 50),
          const ToneSegment(isOn: true, durationMs: 100),
        ],
        700,
      );

      // Total: 50ms + 50ms + 100ms = 200ms
      // Samples: 200 * 8000 / 1000 = 1600
      const expectedSamples = 1600;
      const expectedDataSize = expectedSamples * 2;
      expect(wav.length, 44 + expectedDataSize);
    });

    test('fade envelope produces zero at segment start', () {
      final wav = generator.generate(
        [const ToneSegment(isOn: true, durationMs: 10)],
        700,
      );

      // First sample should be near-zero due to fade-in
      final firstSample = wav[44] | (wav[45] << 8);
      // Allow sign extension for 16-bit
      final signedFirst = firstSample > 32767
          ? firstSample - 65536
          : firstSample;
      expect(signedFirst.abs(), lessThan(500));
    });

    test('default sample rate is 44100', () {
      final defaultGen = WavGenerator();
      final wav = defaultGen.generate(
        [const ToneSegment(isOn: true, durationMs: 100)],
        700,
      );

      final sampleRate =
          wav[24] | (wav[25] << 8) | (wav[26] << 16) | (wav[27] << 24);
      expect(sampleRate, 44100);
    });

    test('empty segment list produces header-only WAV', () {
      final wav = generator.generate([], 700);

      expect(wav.length, 44);

      // Data size should be 0
      final dataSize =
          wav[40] | (wav[41] << 8) | (wav[42] << 16) | (wav[43] << 24);
      expect(dataSize, 0);
    });
  });

  group('ToneSegment', () {
    test('stores isOn and durationMs correctly', () {
      const segment = ToneSegment(isOn: true, durationMs: 500);
      expect(segment.isOn, isTrue);
      expect(segment.durationMs, 500);
    });

    test('can represent silence', () {
      const segment = ToneSegment(isOn: false, durationMs: 200);
      expect(segment.isOn, isFalse);
      expect(segment.durationMs, 200);
    });
  });
}
