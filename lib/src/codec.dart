import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_zstd/src/compressor.dart';
import 'package:dart_zstd/src/dictionary.dart';
import 'package:dart_zstd/src/parameters.dart';
import 'package:dart_zstd/src/stream.dart';

/// Compresses and decompresses with default settings.
const zstd = ZstdCodec();

/// Zstandard, shaped like the codecs in `dart:io`.
///
/// [encode] and [decode] handle whole buffers; [encoder] and [decoder] handle
/// streams of any length. Decoding accepts any number of concatenated frames.
final class ZstdCodec extends Codec<List<int>, List<int>> {
  const ZstdCodec({
    this.level = 0,
    this.checksum = false,
    this.workers = 0,
    this.compressionDictionary,
    this.decompressionDictionary,
  });

  /// From `Zstd.minCompressionLevel` to `Zstd.maxCompressionLevel`; 0 selects
  /// zstd's default.
  final int level;

  /// Whether each frame carries a checksum that decoding verifies.
  final bool checksum;

  /// Threads compression may use. 0 keeps it on the calling isolate's thread.
  final int workers;

  /// Dictionary to compress against. It must stay open for as long as this
  /// codec is used.
  final ZstdCompressionDictionary? compressionDictionary;

  /// Dictionary to decompress against. It must stay open for as long as this
  /// codec is used.
  final ZstdDecompressionDictionary? decompressionDictionary;

  @override
  ZstdEncoder get encoder => ZstdEncoder(
    level: level,
    checksum: checksum,
    workers: workers,
    dictionary: compressionDictionary,
  );

  @override
  ZstdDecoder get decoder => ZstdDecoder(dictionary: decompressionDictionary);

  @override
  Uint8List encode(List<int> input) => encoder.convert(input);

  @override
  Uint8List decode(List<int> encoded) => decoder.convert(encoded);
}

/// Compresses whole buffers with [convert], or a stream through
/// [startChunkedConversion].
final class ZstdEncoder extends Converter<List<int>, List<int>> {
  const ZstdEncoder({
    this.level = 0,
    this.checksum = false,
    this.workers = 0,
    this.dictionary,
  });

  final int level;
  final bool checksum;
  final int workers;

  /// Must stay open for as long as this encoder is used.
  final ZstdCompressionDictionary? dictionary;

  @override
  Uint8List convert(List<int> input) {
    final compressor = ZstdCompressor(level: level);
    try {
      if (checksum) {
        compressor.setParameter(ZstdCompressionParameter.checksumFlag, 1);
      }
      if (workers != 0) {
        compressor.setParameter(ZstdCompressionParameter.workers, workers);
      }
      final dictionary = this.dictionary;
      if (dictionary != null) compressor.useDictionary(dictionary);
      compressor.setPledgedSourceSize(input.length);
      return compressor.compress(input);
    } finally {
      compressor.close();
    }
  }

  @override
  Sink<List<int>> startChunkedConversion(Sink<List<int>> sink) {
    final compressor = ZstdStreamCompressor(level: level);
    if (checksum) {
      compressor.setParameter(ZstdCompressionParameter.checksumFlag, 1);
    }
    if (workers != 0) {
      compressor.setParameter(ZstdCompressionParameter.workers, workers);
    }
    final dictionary = this.dictionary;
    if (dictionary != null) compressor.useDictionary(dictionary);
    return _ZstdEncoderSink(sink, compressor);
  }
}

/// Decompresses whole buffers with [convert], or a stream through
/// [startChunkedConversion].
final class ZstdDecoder extends Converter<List<int>, List<int>> {
  const ZstdDecoder({this.dictionary});

  /// Must stay open for as long as this decoder is used.
  final ZstdDecompressionDictionary? dictionary;

  @override
  Uint8List convert(List<int> input) {
    final builder = BytesBuilder(copy: false);
    final sink = startChunkedConversion(
      ByteConversionSink.withCallback(builder.add),
    )..add(input);
    sink.close();
    return builder.takeBytes();
  }

  @override
  Sink<List<int>> startChunkedConversion(Sink<List<int>> sink) {
    final decompressor = ZstdStreamDecompressor();
    final dictionary = this.dictionary;
    if (dictionary != null) decompressor.useDictionary(dictionary);
    return _ZstdDecoderSink(sink, decompressor);
  }
}

final class _ZstdEncoderSink implements Sink<List<int>> {
  _ZstdEncoderSink(this._sink, this._compressor);

  final Sink<List<int>> _sink;
  final ZstdStreamCompressor _compressor;

  @override
  void add(List<int> chunk) => _compressor.add(chunk, _sink.add);

  @override
  void close() {
    try {
      _compressor.finish(_sink.add);
    } finally {
      _compressor.close();
    }
    _sink.close();
  }
}

final class _ZstdDecoderSink implements Sink<List<int>> {
  _ZstdDecoderSink(this._sink, this._decompressor);

  final Sink<List<int>> _sink;
  final ZstdStreamDecompressor _decompressor;

  @override
  void add(List<int> chunk) => _decompressor.add(chunk, _sink.add);

  @override
  void close() {
    try {
      _decompressor.finish();
    } finally {
      _decompressor.close();
    }
    _sink.close();
  }
}
