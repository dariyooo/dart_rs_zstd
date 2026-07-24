import 'package:dart_zstd/src/bindings.g.dart';
import 'package:dart_zstd/src/exception.dart';
import 'package:dart_zstd/src/native.dart';

/// libzstd returns these in place of a size when the header carries none.
const _contentSizeUnknown = -1;
const _contentSizeError = -2;

/// Reads zstd frame headers without decompressing anything.
abstract final class ZstdFrame {
  /// Whether [data] starts with a zstd frame header.
  static bool isFrame(List<int> data) => withNativeBytes(
    data,
    (pointer, length) => ZSTD_isFrame(pointer.cast(), length) != 0,
  );

  /// Uncompressed size the first frame's header records, or null when it
  /// records none.
  static int? contentSize(List<int> data) =>
      withNativeBytes(data, (pointer, length) {
        final size = ZSTD_getFrameContentSize(pointer.cast(), length);
        if (size == _contentSizeError) {
          throw const ZstdException('not a valid zstd frame header');
        }
        return size == _contentSizeUnknown ? null : size;
      });

  /// Compressed size of the first frame in [data].
  static int compressedSize(List<int> data) => withNativeBytes(
    data,
    (pointer, length) =>
        checkZstd(ZSTD_findFrameCompressedSize(pointer.cast(), length)),
  );

  /// Upper bound on the decompressed size of every frame in [data].
  static int decompressedBound(List<int> data) => withNativeBytes(
    data,
    (pointer, length) =>
        checkZstd(ZSTD_decompressBound(pointer.cast(), length)),
  );

  /// Bytes of [data] the frame header occupies.
  static int headerSize(List<int> data) => withNativeBytes(
    data,
    (pointer, length) =>
        checkZstd(ZSTD_frameHeaderSize(pointer.cast(), length)),
  );

  /// Dictionary id the first frame was compressed with, or null when it
  /// records none.
  static int? dictionaryId(List<int> data) =>
      withNativeBytes(data, (pointer, length) {
        final id = ZSTD_getDictID_fromFrame(pointer.cast(), length);
        return id == 0 ? null : id;
      });
}
