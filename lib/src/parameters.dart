import 'package:dart_zstd/src/bindings.g.dart' as zstd;
import 'package:dart_zstd/src/native.dart';

/// Match finder used while compressing. Later entries trade speed for ratio.
enum ZstdStrategy {
  fast(zstd.ZSTD_strategy.ZSTD_fast),
  dFast(zstd.ZSTD_strategy.ZSTD_dfast),
  greedy(zstd.ZSTD_strategy.ZSTD_greedy),
  lazy(zstd.ZSTD_strategy.ZSTD_lazy),
  lazy2(zstd.ZSTD_strategy.ZSTD_lazy2),
  btLazy2(zstd.ZSTD_strategy.ZSTD_btlazy2),
  btOpt(zstd.ZSTD_strategy.ZSTD_btopt),
  btUltra(zstd.ZSTD_strategy.ZSTD_btultra),
  btUltra2(zstd.ZSTD_strategy.ZSTD_btultra2);

  const ZstdStrategy(this.native);

  final zstd.ZSTD_strategy native;

  /// The value to pass to [ZstdCompressionParameter.strategy].
  int get value => native.value;
}

/// A knob on a compression context.
///
/// Boolean parameters take 0 or 1, and [strategy] takes a [ZstdStrategy.value].
enum ZstdCompressionParameter {
  /// Preset that drives every other parameter. 0 selects zstd's own default.
  compressionLevel(zstd.ZSTD_cParameter.ZSTD_c_compressionLevel),

  /// Maximum back-reference distance, as a power of two.
  windowLog(zstd.ZSTD_cParameter.ZSTD_c_windowLog),
  hashLog(zstd.ZSTD_cParameter.ZSTD_c_hashLog),
  chainLog(zstd.ZSTD_cParameter.ZSTD_c_chainLog),
  searchLog(zstd.ZSTD_cParameter.ZSTD_c_searchLog),
  minMatch(zstd.ZSTD_cParameter.ZSTD_c_minMatch),
  targetLength(zstd.ZSTD_cParameter.ZSTD_c_targetLength),
  strategy(zstd.ZSTD_cParameter.ZSTD_c_strategy),

  /// Size compressed blocks aim for; 0 removes the target.
  targetCBlockSize(zstd.ZSTD_cParameter.ZSTD_c_targetCBlockSize),

  /// Finds matches far apart, which pays off on large redundant inputs.
  enableLongDistanceMatching(
    zstd.ZSTD_cParameter.ZSTD_c_enableLongDistanceMatching,
  ),
  ldmHashLog(zstd.ZSTD_cParameter.ZSTD_c_ldmHashLog),
  ldmMinMatch(zstd.ZSTD_cParameter.ZSTD_c_ldmMinMatch),
  ldmBucketSizeLog(zstd.ZSTD_cParameter.ZSTD_c_ldmBucketSizeLog),
  ldmHashRateLog(zstd.ZSTD_cParameter.ZSTD_c_ldmHashRateLog),

  /// Whether the frame header records the uncompressed size.
  contentSizeFlag(zstd.ZSTD_cParameter.ZSTD_c_contentSizeFlag),

  /// Whether a checksum is appended to each frame.
  checksumFlag(zstd.ZSTD_cParameter.ZSTD_c_checksumFlag),

  /// Whether the frame header records the dictionary id.
  dictIdFlag(zstd.ZSTD_cParameter.ZSTD_c_dictIDFlag),

  /// Worker threads to compress with. 0 keeps compression on the calling
  /// thread; anything else lets the compressor return before a job is done.
  workers(zstd.ZSTD_cParameter.ZSTD_c_nbWorkers),

  /// Bytes each worker takes per job. 0 lets zstd pick.
  jobSize(zstd.ZSTD_cParameter.ZSTD_c_jobSize),

  /// Overlap between worker jobs, from 0 (automatic) to 9 (a full window).
  overlapLog(zstd.ZSTD_cParameter.ZSTD_c_overlapLog);

  const ZstdCompressionParameter(this.native);

  final zstd.ZSTD_cParameter native;

  /// Values libzstd accepts for this parameter, both ends included.
  ({int min, int max}) get bounds {
    final bounds = zstd.ZSTD_cParam_getBounds(native);
    checkZstd(bounds.error);
    return (min: bounds.lowerBound, max: bounds.upperBound);
  }
}

/// A knob on a decompression context.
enum ZstdDecompressionParameter {
  /// Largest window a frame may ask for, as a power of two. Frames needing
  /// more are rejected instead of allocating.
  windowLogMax(zstd.ZSTD_dParameter.ZSTD_d_windowLogMax);

  const ZstdDecompressionParameter(this.native);

  final zstd.ZSTD_dParameter native;

  /// Values libzstd accepts for this parameter, both ends included.
  ({int min, int max}) get bounds {
    final bounds = zstd.ZSTD_dParam_getBounds(native);
    checkZstd(bounds.error);
    return (min: bounds.lowerBound, max: bounds.upperBound);
  }
}

/// How much of a context a reset throws away.
enum ZstdReset {
  /// Abandons the frame in progress, keeping parameters and dictionary.
  session(zstd.ZSTD_ResetDirective.ZSTD_reset_session_only),

  /// Restores default parameters and drops the dictionary. Only allowed
  /// between frames.
  parameters(zstd.ZSTD_ResetDirective.ZSTD_reset_parameters),

  sessionAndParameters(
    zstd.ZSTD_ResetDirective.ZSTD_reset_session_and_parameters,
  );

  const ZstdReset(this.native);

  final zstd.ZSTD_ResetDirective native;
}
