## 0.1.0+zstd.1.5.7

- Direct FFI bindings to libzstd 1.5.7, built from source by `hook/build.dart`
  and shipped as a native asset.
- `ZstdCodec` with buffer and chunked-stream conversion, `ZstdCompressor` and
  `ZstdDecompressor` for reusable contexts, `ZstdStreamCompressor` and
  `ZstdStreamDecompressor` for incremental work.
- Dictionary support: the default, COVER and fastCover trainers with their
  self-optimising modes, `ZstdDictionary.fromContent`, and digested
  dictionaries shareable across contexts.
- Prefix dictionaries, multi-threaded compression, long-distance matching, and
  the full compression parameter set with runtime bounds.
- `ZstdFrame` for reading frame headers without decompressing.
