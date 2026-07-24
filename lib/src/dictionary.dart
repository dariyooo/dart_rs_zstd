import 'dart:ffi';
import 'dart:typed_data';

import 'package:dart_zstd/src/bindings.g.dart';
import 'package:dart_zstd/src/exception.dart';
import 'package:dart_zstd/src/native.dart';
import 'package:dart_zstd/src/native_resource.dart';
import 'package:ffi/ffi.dart';

final _compressionDictionaryFinalizer = NativeFinalizer(
  Native.addressOf<NativeFunction<Size Function(Pointer<ZSTD_CDict>)>>(
    ZSTD_freeCDict,
  ).cast(),
);

final _decompressionDictionaryFinalizer = NativeFinalizer(
  Native.addressOf<NativeFunction<Size Function(Pointer<ZSTD_DDict>)>>(
    ZSTD_freeDDict,
  ).cast(),
);

/// Settings shared by every dictionary trainer.
///
/// Zeroes mean "let zstd decide", which is what you want unless you are tuning.
final class ZstdDictionarySettings {
  const ZstdDictionarySettings({
    this.compressionLevel = 0,
    this.notificationLevel = 0,
    this.dictionaryId = 0,
  });

  /// Level the dictionary is optimised for.
  final int compressionLevel;

  /// How much the trainer writes to stderr, from 0 (silent) to 4.
  final int notificationLevel;

  /// Id written into the dictionary; 0 lets zstd pick a random one.
  final int dictionaryId;
}

/// Tuning for the COVER trainer, which searches for the most useful segments.
final class ZstdCoverSettings {
  const ZstdCoverSettings({
    this.segmentSize = 0,
    this.dmerSize = 0,
    this.steps = 0,
    this.threads = 0,
    this.splitPoint = 0,
    this.shrinkDictionary = false,
    this.shrinkMaxRegression = 0,
    this.settings = const ZstdDictionarySettings(),
  });

  /// Length of the segments COVER selects, typically 16 to 2048.
  final int segmentSize;

  /// Length of the substrings COVER scores, at most 8.
  final int dmerSize;

  /// Parameter combinations an optimising run tries.
  final int steps;

  /// Threads an optimising run may use.
  final int threads;

  /// Fraction of the samples used for training rather than testing.
  final double splitPoint;

  /// Whether to return the smallest dictionary that stays near the best ratio.
  final bool shrinkDictionary;

  /// Percentage of ratio an optimising run may give up while shrinking.
  final int shrinkMaxRegression;

  final ZstdDictionarySettings settings;
}

/// Tuning for the fastCover trainer, a faster approximation of COVER.
final class ZstdFastCoverSettings {
  const ZstdFastCoverSettings({
    this.segmentSize = 0,
    this.dmerSize = 0,
    this.frequencyArrayLog = 0,
    this.steps = 0,
    this.threads = 0,
    this.splitPoint = 0,
    this.acceleration = 0,
    this.shrinkDictionary = false,
    this.shrinkMaxRegression = 0,
    this.settings = const ZstdDictionarySettings(),
  });

  /// Length of the segments the trainer selects, typically 16 to 2048.
  final int segmentSize;

  /// Length of the substrings the trainer scores, at most 8.
  final int dmerSize;

  /// Log of the frequency array size, from 6 to 24. Larger is more accurate.
  final int frequencyArrayLog;

  /// Parameter combinations an optimising run tries.
  final int steps;

  /// Threads an optimising run may use.
  final int threads;

  /// Fraction of the samples used for training rather than testing.
  final double splitPoint;

  /// Speed-up factor from 1 to 10; higher is faster and less accurate.
  final int acceleration;

  /// Whether to return the smallest dictionary that stays near the best ratio.
  final bool shrinkDictionary;

  /// Percentage of ratio an optimising run may give up while shrinking.
  final int shrinkMaxRegression;

  final ZstdDictionarySettings settings;
}

/// A zstd dictionary, interchangeable with the ones the `zstd` command line
/// tool produces.
///
/// Dictionaries pay off on many small inputs that share structure. Whatever a
/// dictionary compressed needs the same dictionary to decompress.
final class ZstdDictionary {
  const ZstdDictionary(this.bytes);

  /// Trains a dictionary of at most [maxSize] bytes.
  ///
  /// zstd wants roughly a hundred samples or more, together at least ten times
  /// the size of the dictionary you ask for, and fails otherwise.
  factory ZstdDictionary.train(
    List<List<int>> samples, {
    required int maxSize,
  }) => _train(samples, maxSize, (dictionary, capacity, buffer, sizes, count) {
    return ZDICT_trainFromBuffer(
      dictionary.cast(),
      capacity,
      buffer.cast(),
      sizes,
      count,
    );
  });

  /// Trains with COVER, which picks dictionary content by scoring segments of
  /// the samples.
  ///
  /// Leaving [ZstdCoverSettings.segmentSize] or [ZstdCoverSettings.dmerSize] at
  /// 0 makes this search for them, which is far slower but needs no tuning.
  factory ZstdDictionary.trainWithCover(
    List<List<int>> samples, {
    required int maxSize,
    ZstdCoverSettings settings = const ZstdCoverSettings(),
  }) => _train(samples, maxSize, (dictionary, capacity, buffer, sizes, count) {
    final params = malloc<ZDICT_cover_params_t>();
    try {
      params.ref
        ..k = settings.segmentSize
        ..d = settings.dmerSize
        ..steps = settings.steps
        ..nbThreads = settings.threads
        ..splitPoint = settings.splitPoint
        ..shrinkDict = settings.shrinkDictionary ? 1 : 0
        ..shrinkDictMaxRegression = settings.shrinkMaxRegression;
      _applySettings(params.ref.zParams, settings.settings);

      final search = settings.segmentSize == 0 || settings.dmerSize == 0;
      return search
          ? ZDICT_optimizeTrainFromBuffer_cover(
              dictionary.cast(),
              capacity,
              buffer.cast(),
              sizes,
              count,
              params,
            )
          : ZDICT_trainFromBuffer_cover(
              dictionary.cast(),
              capacity,
              buffer.cast(),
              sizes,
              count,
              params.ref,
            );
    } finally {
      malloc.free(params);
    }
  });

  /// Trains with fastCover, an approximation of COVER that runs far faster on
  /// large sample sets.
  ///
  /// Leaving [ZstdFastCoverSettings.segmentSize] or
  /// [ZstdFastCoverSettings.dmerSize] at 0 makes this search for them.
  factory ZstdDictionary.trainWithFastCover(
    List<List<int>> samples, {
    required int maxSize,
    ZstdFastCoverSettings settings = const ZstdFastCoverSettings(),
  }) => _train(samples, maxSize, (dictionary, capacity, buffer, sizes, count) {
    final params = malloc<ZDICT_fastCover_params_t>();
    try {
      params.ref
        ..k = settings.segmentSize
        ..d = settings.dmerSize
        ..f = settings.frequencyArrayLog
        ..steps = settings.steps
        ..nbThreads = settings.threads
        ..splitPoint = settings.splitPoint
        ..accel = settings.acceleration
        ..shrinkDict = settings.shrinkDictionary ? 1 : 0
        ..shrinkDictMaxRegression = settings.shrinkMaxRegression;
      _applySettings(params.ref.zParams, settings.settings);

      final search = settings.segmentSize == 0 || settings.dmerSize == 0;
      return search
          ? ZDICT_optimizeTrainFromBuffer_fastCover(
              dictionary.cast(),
              capacity,
              buffer.cast(),
              sizes,
              count,
              params,
            )
          : ZDICT_trainFromBuffer_fastCover(
              dictionary.cast(),
              capacity,
              buffer.cast(),
              sizes,
              count,
              params.ref,
            );
    } finally {
      malloc.free(params);
    }
  });

  /// Turns hand-picked [content] into a dictionary by appending the entropy
  /// tables that make it usable.
  ///
  /// Use this when you already know what the shared content should be, instead
  /// of letting a trainer find it.
  factory ZstdDictionary.fromContent(
    List<int> content,
    List<List<int>> samples, {
    required int maxSize,
    ZstdDictionarySettings settings = const ZstdDictionarySettings(),
  }) => withNativeBytes(content, (contentPointer, contentLength) {
    return _train(samples, maxSize, (
      dictionary,
      capacity,
      buffer,
      sizes,
      count,
    ) {
      final params = malloc<ZDICT_params_t>();
      try {
        _applySettings(params.ref, settings);
        return ZDICT_finalizeDictionary(
          dictionary.cast(),
          capacity,
          contentPointer.cast(),
          contentLength,
          buffer.cast(),
          sizes,
          count,
          params.ref,
        );
      } finally {
        malloc.free(params);
      }
    });
  });

  /// The raw dictionary, ready to be written to disk or shipped as an asset.
  final Uint8List bytes;

  /// Id stored in the dictionary, or null when it carries none.
  int? get id => withNativeBytes(bytes, (pointer, length) {
    final id = ZDICT_getDictID(pointer.cast(), length);
    return id == 0 ? null : id;
  });

  /// Bytes of the dictionary taken up by its header.
  int get headerSize => withNativeBytes(
    bytes,
    (pointer, length) =>
        checkZdict(ZDICT_getDictHeaderSize(pointer.cast(), length)),
  );

  /// Digests this dictionary once so repeated compressions skip that work.
  ///
  /// [level] is baked in; a compressor referencing the result ignores its own
  /// level.
  ZstdCompressionDictionary prepareForCompression({int level = 0}) =>
      ZstdCompressionDictionary(bytes, level: level);

  /// Digests this dictionary once so repeated decompressions skip that work.
  ZstdDecompressionDictionary prepareForDecompression() =>
      ZstdDecompressionDictionary(bytes);
}

/// A dictionary digested for compression, shareable across compressors.
final class ZstdCompressionDictionary extends NativeResource<ZSTD_CDict> {
  factory ZstdCompressionDictionary(List<int> dictionary, {int level = 0}) =>
      ZstdCompressionDictionary._(
        withNativeBytes(dictionary, (pointer, length) {
          final handle = ZSTD_createCDict(pointer.cast(), length, level);
          if (handle == nullptr) {
            throw const ZstdException('could not digest the dictionary');
          }
          return handle;
        }),
      );

  ZstdCompressionDictionary._(Pointer<ZSTD_CDict> handle)
    : super(handle, _compressionDictionaryFinalizer);

  /// Id stored in the dictionary, or null when it carries none.
  int? get id {
    final id = ZSTD_getDictID_fromCDict(handle);
    return id == 0 ? null : id;
  }

  /// Bytes of memory this digested dictionary occupies.
  int get memoryUsage => ZSTD_sizeof_CDict(handle);

  @override
  void release(Pointer<ZSTD_CDict> handle) => ZSTD_freeCDict(handle);
}

/// A dictionary digested for decompression, shareable across decompressors.
final class ZstdDecompressionDictionary extends NativeResource<ZSTD_DDict> {
  factory ZstdDecompressionDictionary(List<int> dictionary) =>
      ZstdDecompressionDictionary._(
        withNativeBytes(dictionary, (pointer, length) {
          final handle = ZSTD_createDDict(pointer.cast(), length);
          if (handle == nullptr) {
            throw const ZstdException('could not digest the dictionary');
          }
          return handle;
        }),
      );

  ZstdDecompressionDictionary._(Pointer<ZSTD_DDict> handle)
    : super(handle, _decompressionDictionaryFinalizer);

  /// Id stored in the dictionary, or null when it carries none.
  int? get id {
    final id = ZSTD_getDictID_fromDDict(handle);
    return id == 0 ? null : id;
  }

  /// Bytes of memory this digested dictionary occupies.
  int get memoryUsage => ZSTD_sizeof_DDict(handle);

  @override
  void release(Pointer<ZSTD_DDict> handle) => ZSTD_freeDDict(handle);
}

void _applySettings(ZDICT_params_t target, ZstdDictionarySettings settings) {
  target
    ..compressionLevel = settings.compressionLevel
    ..notificationLevel = settings.notificationLevel
    ..dictID = settings.dictionaryId;
}

/// Lays the samples out back to back, runs [train], and keeps what it wrote.
ZstdDictionary _train(
  List<List<int>> samples,
  int maxSize,
  int Function(
    Pointer<Uint8> dictionary,
    int capacity,
    Pointer<Uint8> samplesBuffer,
    Pointer<Size> sampleSizes,
    int sampleCount,
  )
  train,
) {
  final total = samples.fold(0, (sum, sample) => sum + sample.length);
  final buffer = malloc<Uint8>(total == 0 ? 1 : total);
  final sizes = malloc<Size>(samples.isEmpty ? 1 : samples.length);
  final dictionary = malloc<Uint8>(maxSize == 0 ? 1 : maxSize);
  try {
    var offset = 0;
    for (var i = 0; i < samples.length; i++) {
      final sample = samples[i];
      buffer.asTypedList(total).setAll(offset, sample);
      sizes[i] = sample.length;
      offset += sample.length;
    }

    final written = checkZdict(
      train(dictionary, maxSize, buffer, sizes, samples.length),
    );
    return ZstdDictionary(Uint8List.fromList(dictionary.asTypedList(written)));
  } finally {
    malloc
      ..free(buffer)
      ..free(sizes)
      ..free(dictionary);
  }
}
