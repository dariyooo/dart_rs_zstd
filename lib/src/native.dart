import 'dart:ffi';
import 'dart:typed_data';

import 'package:dart_zstd/src/bindings.g.dart';
import 'package:dart_zstd/src/exception.dart';
import 'package:ffi/ffi.dart';

/// Returns [code], or throws when libzstd encoded an error in it.
int checkZstd(int code) {
  if (ZSTD_isError(code) != 0) {
    throw ZstdException(ZSTD_getErrorName(code).cast<Utf8>().toDartString());
  }
  return code;
}

/// Returns [code], or throws when the dictionary builder encoded an error in it.
int checkZdict(int code) {
  if (ZDICT_isError(code) != 0) {
    throw ZstdException(ZDICT_getErrorName(code).cast<Utf8>().toDartString());
  }
  return code;
}

/// Copies [data] into native memory and releases it once [body] returns.
R withNativeBytes<R>(
  List<int> data,
  R Function(Pointer<Uint8> pointer, int length) body,
) {
  final length = data.length;
  if (length == 0) return body(nullptr, 0);

  final pointer = malloc<Uint8>(length);
  try {
    pointer.asTypedList(length).setAll(0, data);
    return body(pointer, length);
  } finally {
    malloc.free(pointer);
  }
}

/// Runs [body] against a scratch buffer of [capacity] bytes and returns the
/// first `body(...)` bytes of it.
Uint8List intoNativeBuffer(
  int capacity,
  int Function(Pointer<Uint8> pointer, int capacity) body,
) {
  if (capacity == 0) return Uint8List(0);

  final pointer = malloc<Uint8>(capacity);
  try {
    final written = body(pointer, capacity);
    return Uint8List.fromList(pointer.asTypedList(written));
  } finally {
    malloc.free(pointer);
  }
}
