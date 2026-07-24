import 'dart:ffi';
import 'dart:typed_data';

import 'package:dart_zstd/src/bindings.g.dart';
import 'package:dart_zstd/src/dictionary.dart';
import 'package:dart_zstd/src/exception.dart';
import 'package:dart_zstd/src/frame.dart';
import 'package:dart_zstd/src/native.dart';
import 'package:dart_zstd/src/native_resource.dart';
import 'package:dart_zstd/src/parameters.dart';
import 'package:ffi/ffi.dart';

final _decompressorFinalizer = NativeFinalizer(
  Native.addressOf<NativeFunction<Size Function(Pointer<ZSTD_DCtx>)>>(
    ZSTD_freeDCtx,
  ).cast(),
);

/// Decompresses whole frames, reusing one zstd context across calls.
///
/// Every call takes an explicit size bound, so a hostile frame cannot make the
/// process allocate more than the caller allows.
final class ZstdDecompressor extends NativeResource<ZSTD_DCtx> {
  factory ZstdDecompressor() =>
      ZstdDecompressor._(createDecompressionContext());

  ZstdDecompressor._(Pointer<ZSTD_DCtx> handle)
    : super(handle, _decompressorFinalizer);

  /// Decompresses one frame, refusing output larger than [maxSize].
  ///
  /// Leaving [maxSize] out uses the size recorded in the frame header, and
  /// fails when the header records none.
  Uint8List decompress(List<int> data, {int? maxSize}) {
    final capacity = maxSize ?? ZstdFrame.contentSize(data);
    if (capacity == null) {
      throw const ZstdException(
        'the frame does not record its size, so maxSize is required',
      );
    }
    return withNativeBytes(
      data,
      (source, length) => intoNativeBuffer(
        capacity,
        (destination, bound) => checkZstd(
          ZSTD_decompressDCtx(
            handle,
            destination.cast(),
            bound,
            source.cast(),
            length,
          ),
        ),
      ),
    );
  }

  /// Decompresses one frame into [destination], returning the bytes written.
  int decompressInto(List<int> data, Uint8List destination) =>
      withNativeBytes(data, (source, length) {
        final output = malloc<Uint8>(
          destination.isEmpty ? 1 : destination.length,
        );
        try {
          final written = checkZstd(
            ZSTD_decompressDCtx(
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

  void setParameter(ZstdDecompressionParameter parameter, int value) =>
      checkZstd(ZSTD_DCtx_setParameter(handle, parameter.native, value));

  /// Loads a raw dictionary, digesting it into this context.
  ///
  /// Prefer [useDictionary] when the same dictionary serves several
  /// decompressions.
  void loadDictionary(List<int> dictionary) => withNativeBytes(
    dictionary,
    (pointer, length) =>
        checkZstd(ZSTD_DCtx_loadDictionary(handle, pointer.cast(), length)),
  );

  /// References an already digested dictionary, which must stay open for as
  /// long as this decompressor uses it.
  void useDictionary(ZstdDecompressionDictionary dictionary) =>
      checkZstd(ZSTD_DCtx_refDDict(handle, dictionary.handle));

  /// Uses [prefix] as raw content preceding the next frame. It must match the
  /// prefix the compressor used.
  void usePrefix(List<int> prefix) => withNativeBytes(
    prefix,
    (pointer, length) =>
        checkZstd(ZSTD_DCtx_refPrefix(handle, pointer.cast(), length)),
  );

  /// Drops the dictionary and any prefix, leaving other parameters alone.
  void clearDictionary() => checkZstd(ZSTD_DCtx_refDDict(handle, nullptr));

  void reset({ZstdReset directive = ZstdReset.sessionAndParameters}) =>
      checkZstd(ZSTD_DCtx_reset(handle, directive.native));

  /// Bytes of memory this context currently holds.
  int get memoryUsage => ZSTD_sizeof_DCtx(handle);

  @override
  void release(Pointer<ZSTD_DCtx> handle) => ZSTD_freeDCtx(handle);
}

/// Allocates a decompression context, or throws when zstd cannot.
Pointer<ZSTD_DCtx> createDecompressionContext() {
  final handle = ZSTD_createDCtx();
  if (handle == nullptr) {
    throw const ZstdException('could not allocate a decompression context');
  }
  return handle;
}
