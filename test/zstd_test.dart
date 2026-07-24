import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_zstd/dart_zstd.dart';
import 'package:test/test.dart';

import 'utils/zstd_test_cases.dart';

void main() {
  group('round trip', () {
    for (final testCase in roundTripCases) {
      test(testCase.description, () {
        final codec = ZstdCodec(level: testCase.level);
        final packed = codec.encode(testCase.payload);
        expect(codec.decode(packed), equals(testCase.payload));
      });
    }
  });

  group('frame header', () {
    for (final testCase in roundTripCases) {
      test(testCase.description, () {
        final packed = ZstdCodec(
          level: testCase.level,
        ).encode(testCase.payload);
        expect(ZstdFrame.isFrame(packed), isTrue);
        expect(ZstdFrame.contentSize(packed), equals(testCase.payload.length));
        expect(ZstdFrame.compressedSize(packed), equals(packed.length));
        expect(
          ZstdFrame.decompressedBound(packed),
          greaterThanOrEqualTo(testCase.payload.length),
        );
      });
    }
  });

  group('streamed in chunks', () {
    for (final testCase in chunkedCases) {
      test(testCase.description, () async {
        final packed = await _pipe(
          _split(testCase.payload, testCase.chunkSize),
          zstd.encoder,
        );
        expect(zstd.decode(packed), equals(testCase.payload));

        final unpacked = await _pipe(
          _split(packed, testCase.chunkSize),
          zstd.decoder,
        );
        expect(unpacked, equals(testCase.payload));
      });
    }
  });

  group('rejects', () {
    for (final testCase in rejectionCases) {
      test(testCase.description, () {
        expect(
          () => zstd.decode(testCase.input),
          throwsA(
            isA<ZstdException>().having(
              (error) => error.message,
              'message',
              contains(testCase.reason),
            ),
          ),
        );
      });
    }
  });

  test('decodes concatenated frames as one stream', () {
    final first = zstd.encode(const [1, 2, 3]);
    final second = zstd.encode(const [4, 5, 6]);
    expect(zstd.decode([...first, ...second]), equals([1, 2, 3, 4, 5, 6]));
  });

  test('a checksummed frame rejects a flipped bit', () {
    final codec = ZstdCodec(checksum: true);
    final packed = codec.encode(dictionarySamples.first);
    packed[packed.length - 2] ^= 0xff;
    expect(() => codec.decode(packed), throwsA(isA<ZstdException>()));
  });

  test('pledging the wrong source size fails on finish', () {
    final compressor = ZstdStreamCompressor()..setPledgedSourceSize(1000);
    addTearDown(compressor.close);
    compressor.add(const [1, 2, 3], (_) {});
    expect(() => compressor.finish((_) {}), throwsA(isA<ZstdException>()));
  });

  group('dictionary', () {
    late ZstdDictionary dictionary;
    late ZstdCompressionDictionary forCompression;
    late ZstdDecompressionDictionary forDecompression;
    late ZstdCodec codec;

    setUpAll(() {
      dictionary = ZstdDictionary.train(dictionarySamples, maxSize: 8 * 1024);
      forCompression = dictionary.prepareForCompression(level: 10);
      forDecompression = dictionary.prepareForDecompression();
      codec = ZstdCodec(
        compressionDictionary: forCompression,
        decompressionDictionary: forDecompression,
      );
    });

    tearDownAll(() {
      forCompression.close();
      forDecompression.close();
    });

    test('beats compressing a small record without one', () {
      final record = dictionarySamples.first;
      expect(codec.encode(record).length, lessThan(zstd.encode(record).length));
    });

    test('round trips every sample', () {
      for (final sample in dictionarySamples) {
        expect(codec.decode(codec.encode(sample)), equals(sample));
      }
    });

    test('stamps its id into the frame', () {
      expect(dictionary.id, isNotNull);
      expect(forCompression.id, equals(dictionary.id));
      expect(
        ZstdFrame.dictionaryId(codec.encode(dictionarySamples.first)),
        equals(dictionary.id),
      );
    });

    test('a frame needs the dictionary that wrote it', () {
      expect(
        () => zstd.decode(codec.encode(dictionarySamples.first)),
        throwsA(isA<ZstdException>()),
      );
    });

    test('fastCover trains a usable dictionary', () {
      final trained = ZstdDictionary.trainWithFastCover(
        dictionarySamples,
        maxSize: 8 * 1024,
        settings: const ZstdFastCoverSettings(segmentSize: 64, dmerSize: 8),
      );
      final compression = trained.prepareForCompression();
      final decompression = trained.prepareForDecompression();
      addTearDown(compression.close);
      addTearDown(decompression.close);

      final withDictionary = ZstdCodec(
        compressionDictionary: compression,
        decompressionDictionary: decompression,
      );
      final record = dictionarySamples.first;
      expect(withDictionary.decode(withDictionary.encode(record)), record);
    });
  });

  group('prefix', () {
    test('round trips when both sides use the same prefix', () {
      final prefix = dictionarySamples.first;
      final record = dictionarySamples.last;

      final compressor = ZstdCompressor()..usePrefix(prefix);
      addTearDown(compressor.close);
      final packed = compressor.compress(record);

      final decompressor = ZstdDecompressor()..usePrefix(prefix);
      addTearDown(decompressor.close);
      expect(decompressor.decompress(packed), equals(record));
    });
  });

  test('a closed resource refuses further use', () {
    final compressor = ZstdCompressor()..close();
    expect(compressor.isClosed, isTrue);
    expect(() => compressor.compress(const [1]), throwsStateError);
  });

  test('parameter bounds bracket the documented defaults', () {
    final level = ZstdCompressionParameter.compressionLevel.bounds;
    expect(level.min, equals(Zstd.minCompressionLevel));
    expect(level.max, equals(Zstd.maxCompressionLevel));

    final strategy = ZstdCompressionParameter.strategy.bounds;
    expect(strategy.max, equals(ZstdStrategy.btUltra2.value));
  });
}

List<List<int>> _split(List<int> data, int chunkSize) => [
  for (var offset = 0; offset < data.length; offset += chunkSize)
    data.sublist(offset, (offset + chunkSize).clamp(0, data.length)),
];

Future<Uint8List> _pipe(
  List<List<int>> chunks,
  Converter<List<int>, List<int>> converter,
) async {
  final builder = BytesBuilder();
  await Stream<List<int>>.fromIterable(
    chunks,
  ).transform(converter).forEach(builder.add);
  return builder.takeBytes();
}
