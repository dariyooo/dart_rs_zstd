/// Zstandard compression, backed by the reference libzstd implementation
/// bundled as a native asset.
library;

export 'src/codec.dart' show ZstdCodec, ZstdDecoder, ZstdEncoder, zstd;
export 'src/compressor.dart' show ZstdCompressor;
export 'src/decompressor.dart' show ZstdDecompressor;
export 'src/dictionary.dart'
    show
        ZstdCompressionDictionary,
        ZstdCoverSettings,
        ZstdDecompressionDictionary,
        ZstdDictionary,
        ZstdDictionarySettings,
        ZstdFastCoverSettings;
export 'src/exception.dart' show ZstdException;
export 'src/frame.dart' show ZstdFrame;
export 'src/parameters.dart'
    show
        ZstdCompressionParameter,
        ZstdDecompressionParameter,
        ZstdReset,
        ZstdStrategy;
export 'src/stream.dart'
    show ZstdOutput, ZstdStreamCompressor, ZstdStreamDecompressor;
export 'src/zstd_library.dart' show Zstd;
