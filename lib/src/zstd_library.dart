import 'package:dart_zstd/src/bindings.g.dart';
import 'package:ffi/ffi.dart';

/// Facts about the bundled libzstd.
abstract final class Zstd {
  /// Version of libzstd, for example `1.5.7`.
  static String get version => ZSTD_versionString().cast<Utf8>().toDartString();

  /// [version] as `major * 10000 + minor * 100 + patch`.
  static int get versionNumber => ZSTD_versionNumber();

  /// Fastest level, a negative number. Levels below 0 trade ratio for speed.
  static int get minCompressionLevel => ZSTD_minCLevel();

  /// Slowest and densest level.
  static int get maxCompressionLevel => ZSTD_maxCLevel();

  /// Level applied when a level of 0 is requested.
  static int get defaultCompressionLevel => ZSTD_defaultCLevel();

  /// Worst-case compressed size for [sourceSize] bytes of input.
  static int compressBound(int sourceSize) => ZSTD_compressBound(sourceSize);

  /// Input size the streaming compressor prefers per step.
  static int get streamInputSize => ZSTD_CStreamInSize();

  /// Output size the streaming compressor prefers per step.
  static int get streamOutputSize => ZSTD_CStreamOutSize();
}
