import 'dart:ffi';
import 'dart:typed_data';

import 'package:dart_zstd/src/bindings.g.dart';
import 'package:dart_zstd/src/dictionary.dart';
import 'package:dart_zstd/src/exception.dart';
import 'package:dart_zstd/src/native.dart';
import 'package:dart_zstd/src/native_resource.dart';
import 'package:dart_zstd/src/parameters.dart';
import 'package:dart_zstd/src/zstd_library.dart';
import 'package:ffi/ffi.dart';

final _compressorFinalizer = NativeFinalizer(
  Native.addressOf<NativeFunction<Size Function(Pointer<ZSTD_CCtx>)>>(
    ZSTD_freeCCtx,
  ).cast(),
);

/// Compresses whole buffers, reusing one zstd context across calls.
///
/// Reusing the context avoids reallocating zstd's tables per call, which is
/// what makes this the right tool for many small payloads. Input that does not
/// fit in memory belongs in `ZstdEncoder` instead.
final class ZstdCompressor extends NativeResource<ZSTD_CCtx> {
  /// [level] ranges from [Zstd.minCompressionLevel] to
  /// [Zstd.maxCompressionLevel]; 0 selects zstd's default.
  factory ZstdCompressor({int level = 0}) {
    final compressor = ZstdCompressor._(createCompressionContext());
    if (level != 0) compressor.setLevel(level);
    return compressor;
  }

  ZstdCompressor._(Pointer<ZSTD_CCtx> handle)
    : super(handle, _compressorFinalizer);

  /// Compresses [data] into a single frame.
  Uint8List compress(List<int> data) => withNativeBytes(
    data,
    (source, length) => intoNativeBuffer(
      ZSTD_compressBound(length),
      (destination, capacity) => checkZstd(
        ZSTD_compress2(
          handle,
          destination.cast(),
          capacity,
          source.cast(),
          length,
        ),
      ),
    ),
  );

  /// Compresses [data] into [destination], returning the bytes written.
  ///
  /// [destination] needs [Zstd.compressBound] bytes to be safe for any input.
  int compressInto(List<int> data, Uint8List destination) =>
      withNativeBytes(data, (source, length) {
        final output = malloc<Uint8>(
          destination.isEmpty ? 1 : destination.length,
        );
        try {
          final written = checkZstd(
            ZSTD_compress2(
              handle,
              output.cast(),
              destination.length,
              source.cast(),
              length,
            ),
          );
          destination.setRange(0, written, output.asTypedList(written));
          return written;
        } finally {
          malloc.free(output);
        }
      });

  void setLevel(int level) =>
      setParameter(ZstdCompressionParameter.compressionLevel, level);

  /// Boolean parameters take 0 or 1; [ZstdCompressionParameter.strategy] takes
  /// a [ZstdStrategy.value].
  void setParameter(ZstdCompressionParameter parameter, int value) =>
      checkZstd(ZSTD_CCtx_setParameter(handle, parameter.native, value));

  /// Declares the exact uncompressed size of the next frame, which lets zstd
  /// record it in the header and size its tables. Compressing a different
  /// amount then fails.
  void setPledgedSourceSize(int? size) => checkZstd(
    ZSTD_CCtx_setPledgedSrcSize(handle, size ?? _contentSizeUnknown),
  );

  /// Loads a raw dictionary, digesting it into this context.
  ///
  /// Prefer [useDictionary] when the same dictionary serves several
  /// compressions.
  void loadDictionary(List<int> dictionary) => withNativeBytes(
    dictionary,
    (pointer, length) =>
        checkZstd(ZSTD_CCtx_loadDictionary(handle, pointer.cast(), length)),
  );

  /// References an already digested dictionary, which must stay open for as
  /// long as this compressor uses it.
  void useDictionary(ZstdCompressionDictionary dictionary) =>
      checkZstd(ZSTD_CCtx_refCDict(handle, dictionary.handle));

  /// Uses [prefix] as raw content preceding the next frame.
  ///
  /// Unlike a dictionary this holds for one frame only, and the decompressor
  /// needs the same prefix.
  void usePrefix(List<int> prefix) => withNativeBytes(
    prefix,
    (pointer, length) =>
        checkZstd(ZSTD_CCtx_refPrefix(handle, pointer.cast(), length)),
  );

  /// Drops the dictionary and any prefix, leaving other parameters alone.
  void clearDictionary() => checkZstd(ZSTD_CCtx_refCDict(handle, nullptr));

  void reset({ZstdReset directive = ZstdReset.sessionAndParameters}) =>
      checkZstd(ZSTD_CCtx_reset(handle, directive.native));

  /// Bytes of memory this context currently holds.
  int get memoryUsage => ZSTD_sizeof_CCtx(handle);

  @override
  void release(Pointer<ZSTD_CCtx> handle) => ZSTD_freeCCtx(handle);
}

/// libzstd's sentinel for "size not known in advance".
const _contentSizeUnknown = -1;

/// Allocates a compression context, or throws when zstd cannot.
Pointer<ZSTD_CCtx> createCompressionContext() {
  final handle = ZSTD_createCCtx();
  if (handle == nullptr) {
    throw const ZstdException('could not allocate a compression context');
  }
  return handle;
}
