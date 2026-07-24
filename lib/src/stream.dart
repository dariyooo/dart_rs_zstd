import 'dart:ffi';
import 'dart:typed_data';

import 'package:dart_zstd/src/bindings.g.dart';
import 'package:dart_zstd/src/compressor.dart';
import 'package:dart_zstd/src/decompressor.dart';
import 'package:dart_zstd/src/dictionary.dart';
import 'package:dart_zstd/src/exception.dart';
import 'package:dart_zstd/src/native.dart';
import 'package:dart_zstd/src/native_resource.dart';
import 'package:dart_zstd/src/parameters.dart';
import 'package:ffi/ffi.dart';

/// A block of output handed back as it becomes available.
typedef ZstdOutput = void Function(Uint8List block);

final _streamCompressorFinalizer = NativeFinalizer(
  Native.addressOf<NativeFunction<Size Function(Pointer<ZSTD_CCtx>)>>(
    ZSTD_freeCCtx,
  ).cast(),
);

final _streamDecompressorFinalizer = NativeFinalizer(
  Native.addressOf<NativeFunction<Size Function(Pointer<ZSTD_DCtx>)>>(
    ZSTD_freeDCtx,
  ).cast(),
);

/// Compresses input piece by piece into one frame.
///
/// Feed with [add], then call [finish] exactly once to write the frame
/// epilogue. Output arrives through the callback as zstd produces it, so
/// nothing larger than one buffer is ever held.
final class ZstdStreamCompressor extends NativeResource<ZSTD_CCtx> {
  factory ZstdStreamCompressor({int level = 0}) {
    final compressor = ZstdStreamCompressor._(createCompressionContext());
    if (level != 0) compressor.setLevel(level);
    return compressor;
  }

  ZstdStreamCompressor._(Pointer<ZSTD_CCtx> handle)
    : _buffer = _StreamBuffers(ZSTD_CStreamOutSize()),
      super(handle, _streamCompressorFinalizer) {
    _buffer.attachTo(this);
  }

  final _StreamBuffers _buffer;

  /// Compresses [data], handing every finished block to [onOutput].
  void add(List<int> data, ZstdOutput onOutput) {
    if (data.isEmpty) return;
    withNativeBytes(data, (source, length) {
      _buffer.setInput(source, length);
      while (_buffer.input.ref.pos < length) {
        _step(ZSTD_EndDirective.ZSTD_e_continue, onOutput);
      }
      _buffer.clearInput();
    });
  }

  /// Pushes out everything buffered so far without ending the frame.
  ///
  /// Costs ratio: it forces a block boundary. Use it when a reader needs the
  /// data before the stream ends.
  void flush(ZstdOutput onOutput) =>
      _drain(ZSTD_EndDirective.ZSTD_e_flush, onOutput);

  /// Writes the frame epilogue. The compressor can start a new frame after
  /// this.
  void finish(ZstdOutput onOutput) =>
      _drain(ZSTD_EndDirective.ZSTD_e_end, onOutput);

  void setLevel(int level) =>
      setParameter(ZstdCompressionParameter.compressionLevel, level);

  void setParameter(ZstdCompressionParameter parameter, int value) =>
      checkZstd(ZSTD_CCtx_setParameter(handle, parameter.native, value));

  /// Declares the exact uncompressed size of the frame. Finishing after a
  /// different amount fails.
  void setPledgedSourceSize(int? size) =>
      checkZstd(ZSTD_CCtx_setPledgedSrcSize(handle, size ?? -1));

  void loadDictionary(List<int> dictionary) => withNativeBytes(
    dictionary,
    (pointer, length) =>
        checkZstd(ZSTD_CCtx_loadDictionary(handle, pointer.cast(), length)),
  );

  /// References an already digested dictionary, which must stay open for as
  /// long as this compressor uses it.
  void useDictionary(ZstdCompressionDictionary dictionary) =>
      checkZstd(ZSTD_CCtx_refCDict(handle, dictionary.handle));

  /// Uses [prefix] as raw content preceding the frame.
  void usePrefix(List<int> prefix) => withNativeBytes(
    prefix,
    (pointer, length) =>
        checkZstd(ZSTD_CCtx_refPrefix(handle, pointer.cast(), length)),
  );

  void reset({ZstdReset directive = ZstdReset.session}) =>
      checkZstd(ZSTD_CCtx_reset(handle, directive.native));

  void _drain(ZSTD_EndDirective directive, ZstdOutput onOutput) {
    _buffer.clearInput();
    int remaining;
    do {
      remaining = _step(directive, onOutput);
    } while (remaining != 0);
  }

  int _step(ZSTD_EndDirective directive, ZstdOutput onOutput) {
    _buffer.output.ref.pos = 0;
    final remaining = checkZstd(
      ZSTD_compressStream2(handle, _buffer.output, _buffer.input, directive),
    );
    _buffer.emit(onOutput);
    return remaining;
  }

  @override
  void release(Pointer<ZSTD_CCtx> handle) {
    _buffer.free();
    ZSTD_freeCCtx(handle);
  }
}

/// Decompresses input piece by piece, across any number of concatenated
/// frames.
///
/// Feed with [add], then call [finish] once, which fails if the input stopped
/// mid-frame.
final class ZstdStreamDecompressor extends NativeResource<ZSTD_DCtx> {
  factory ZstdStreamDecompressor() =>
      ZstdStreamDecompressor._(createDecompressionContext());

  ZstdStreamDecompressor._(Pointer<ZSTD_DCtx> handle)
    : _buffer = _StreamBuffers(ZSTD_DStreamOutSize()),
      super(handle, _streamDecompressorFinalizer) {
    _buffer.attachTo(this);
  }

  final _StreamBuffers _buffer;

  /// Non-zero while zstd is waiting for the rest of a frame.
  int _pending = 0;

  /// Decompresses [data], handing every finished block to [onOutput].
  void add(List<int> data, ZstdOutput onOutput) {
    if (data.isEmpty) return;
    withNativeBytes(data, (source, length) {
      _buffer.setInput(source, length);
      // A step that exactly fills the output may have left more behind, so keep
      // going until one comes back short.
      var filled = false;
      while (_buffer.input.ref.pos < length || filled) {
        _buffer.output.ref.pos = 0;
        _pending = checkZstd(
          ZSTD_decompressStream(handle, _buffer.output, _buffer.input),
        );
        filled = _buffer.output.ref.pos == _buffer.capacity;
        _buffer.emit(onOutput);
      }
      _buffer.clearInput();
    });
  }

  /// Checks that the input ended on a frame boundary.
  void finish() {
    if (_pending != 0) {
      throw const ZstdException('the input ended in the middle of a frame');
    }
  }

  void setParameter(ZstdDecompressionParameter parameter, int value) =>
      checkZstd(ZSTD_DCtx_setParameter(handle, parameter.native, value));

  void loadDictionary(List<int> dictionary) => withNativeBytes(
    dictionary,
    (pointer, length) =>
        checkZstd(ZSTD_DCtx_loadDictionary(handle, pointer.cast(), length)),
  );

  /// References an already digested dictionary, which must stay open for as
  /// long as this decompressor uses it.
  void useDictionary(ZstdDecompressionDictionary dictionary) =>
      checkZstd(ZSTD_DCtx_refDDict(handle, dictionary.handle));

  /// Uses [prefix] as raw content preceding the frame. It must match the
  /// prefix the compressor used.
  void usePrefix(List<int> prefix) => withNativeBytes(
    prefix,
    (pointer, length) =>
        checkZstd(ZSTD_DCtx_refPrefix(handle, pointer.cast(), length)),
  );

  void reset({ZstdReset directive = ZstdReset.session}) {
    checkZstd(ZSTD_DCtx_reset(handle, directive.native));
    _pending = 0;
  }

  @override
  void release(Pointer<ZSTD_DCtx> handle) {
    _buffer.free();
    ZSTD_freeDCtx(handle);
  }
}

/// The `ZSTD_inBuffer`/`ZSTD_outBuffer` pair a streaming context works through,
/// plus the scratch space they point at.
///
/// One allocation holds all three, so a single finalizer covers them.
final class _StreamBuffers {
  factory _StreamBuffers(int capacity) {
    final inputOffset = 0;
    final outputOffset = sizeOf<ZSTD_inBuffer>();
    final scratchOffset = outputOffset + sizeOf<ZSTD_outBuffer>();
    final block = malloc<Uint8>(scratchOffset + capacity);
    return _StreamBuffers._(
      capacity,
      block,
      (block + inputOffset).cast(),
      (block + outputOffset).cast(),
      block + scratchOffset,
    );
  }

  _StreamBuffers._(
    this.capacity,
    this._block,
    this.input,
    this.output,
    this._scratch,
  ) {
    output.ref
      ..dst = _scratch.cast()
      ..size = capacity
      ..pos = 0;
    clearInput();
  }

  final int capacity;
  final Pointer<Uint8> _block;
  final Pointer<ZSTD_inBuffer> input;
  final Pointer<ZSTD_outBuffer> output;
  final Pointer<Uint8> _scratch;

  /// Releases the block if [owner] is collected before it is closed.
  void attachTo(Finalizable owner) =>
      _bufferFinalizer.attach(owner, _block.cast(), detach: this);

  void setInput(Pointer<Uint8> source, int length) => input.ref
    ..src = source.cast()
    ..size = length
    ..pos = 0;

  void clearInput() => input.ref
    ..src = nullptr
    ..size = 0
    ..pos = 0;

  void emit(ZstdOutput onOutput) {
    final written = output.ref.pos;
    if (written == 0) return;
    onOutput(Uint8List.fromList(_scratch.asTypedList(written)));
  }

  void free() {
    _bufferFinalizer.detach(this);
    malloc.free(_block);
  }
}

final _bufferFinalizer = NativeFinalizer(malloc.nativeFree);
