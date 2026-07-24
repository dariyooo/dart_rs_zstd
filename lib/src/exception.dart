/// Thrown when libzstd rejects an operation.
final class ZstdException implements Exception {
  const ZstdException(this.message);

  final String message;

  @override
  String toString() => 'ZstdException: $message';
}
