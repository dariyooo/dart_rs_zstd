import 'dart:ffi';

/// Owns a native handle that [close] releases, and that the garbage collector
/// releases if the wrapper is dropped first.
abstract base class NativeResource<T extends NativeType>
    implements Finalizable {
  NativeResource(this._handle, NativeFinalizer finalizer)
    : _finalizer = finalizer {
    finalizer.attach(this, _handle.cast(), detach: this);
  }

  final NativeFinalizer _finalizer;
  Pointer<T> _handle;

  bool get isClosed => _handle == nullptr;

  Pointer<T> get handle {
    if (_handle == nullptr) {
      throw StateError('$runtimeType has already been closed');
    }
    return _handle;
  }

  /// Releases the native handle. Calling it again does nothing.
  void close() {
    if (_handle == nullptr) return;
    _finalizer.detach(this);
    release(_handle);
    _handle = nullptr;
  }

  void release(Pointer<T> handle);
}
