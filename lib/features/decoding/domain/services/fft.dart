import 'dart:math';
import 'dart:typed_data';

/// Radix-2 Cooley-Tukey FFT implementation in pure Dart.
///
/// Used for wideband scanning in the 400-1000 Hz range to
/// find the strongest tone before locking on with IIR bandpass.
class FFT {
  FFT(this.size)
    : assert(
        _isPowerOfTwo(size),
        'Size must be '
        'a power of 2',
      ) {
    _initTwiddleFactors();
  }

  final int size;

  late final Float64List _cosTable = Float64List(size ~/ 2);
  late final Float64List _sinTable = Float64List(size ~/ 2);

  static bool _isPowerOfTwo(int n) {
    return n > 0 && (n & (n - 1)) == 0;
  }

  void _initTwiddleFactors() {
    for (var i = 0; i < size ~/ 2; i++) {
      final angle = -2 * pi * i / size;
      _cosTable[i] = cos(angle);
      _sinTable[i] = sin(angle);
    }
  }

  /// In-place FFT transform.
  ///
  /// [real] and [imag] must have length [size].
  void transform(Float64List real, Float64List imag) {
    _bitReverse(real, imag);

    for (var step = 2; step <= size; step *= 2) {
      final halfStep = step ~/ 2;
      final twiddleStep = size ~/ step;
      for (var i = 0; i < size; i += step) {
        for (var j = 0; j < halfStep; j++) {
          final wr = _cosTable[j * twiddleStep];
          final wi = _sinTable[j * twiddleStep];
          final idx1 = i + j;
          final idx2 = i + j + halfStep;
          final tr = wr * real[idx2] - wi * imag[idx2];
          final ti = wr * imag[idx2] + wi * real[idx2];
          real[idx2] = real[idx1] - tr;
          imag[idx2] = imag[idx1] - ti;
          real[idx1] += tr;
          imag[idx1] += ti;
        }
      }
    }
  }

  /// Computes the power spectrum (magnitude squared) of
  /// [samples]. Returns [size / 2] bins.
  Float64List powerSpectrum(Float64List samples) {
    final real = Float64List(size);
    final imag = Float64List(size);
    final n = samples.length < size ? samples.length : size;
    for (var i = 0; i < n; i++) {
      real[i] = samples[i];
    }
    transform(real, imag);
    final power = Float64List(size ~/ 2);
    for (var i = 0; i < power.length; i++) {
      power[i] = real[i] * real[i] + imag[i] * imag[i];
    }
    return power;
  }

  /// Returns the frequency of bin [bin] at [sampleRate].
  double binFrequency(int bin, int sampleRate) {
    return bin * sampleRate / size;
  }

  /// Returns the bin index closest to [frequency] at
  /// [sampleRate].
  int frequencyToBin(double frequency, int sampleRate) {
    return (frequency * size / sampleRate).round();
  }

  void _bitReverse(Float64List real, Float64List imag) {
    var j = 0;
    for (var i = 1; i < size; i++) {
      var bit = size >> 1;
      while ((j & bit) != 0) {
        j ^= bit;
        bit >>= 1;
      }
      j ^= bit;
      if (i < j) {
        final tr = real[i];
        real[i] = real[j];
        real[j] = tr;
        final ti = imag[i];
        imag[i] = imag[j];
        imag[j] = ti;
      }
    }
  }
}
