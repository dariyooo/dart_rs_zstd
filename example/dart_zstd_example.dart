import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_zstd/dart_zstd.dart';

Future<void> main() async {
  print(
    'libzstd ${Zstd.version}, levels '
    '${Zstd.minCompressionLevel}..${Zstd.maxCompressionLevel} '
    '(default ${Zstd.defaultCompressionLevel})',
  );

  final payload = utf8.encode('the quick brown fox ' * 200);

  final packed = zstd.encode(payload);
  print('one shot: ${payload.length} -> ${packed.length} bytes');
  print('round trip: ${_same(zstd.decode(packed), payload)}');

  final dense = const ZstdCodec(level: 19, checksum: true).encode(payload);
  print('level 19 + checksum: ${dense.length} bytes');

  print(
    'frame says ${ZstdFrame.contentSize(packed)} bytes of content, '
    'occupying ${ZstdFrame.compressedSize(packed)}',
  );

  final streamed = await Stream<List<int>>.fromIterable([
    payload.sublist(0, 1000),
    payload.sublist(1000),
  ]).transform(zstd.encoder).fold(BytesBuilder(), (b, c) => b..add(c));
  print(
    'streamed: ${streamed.length} bytes, round trip '
    '${_same(zstd.decode(streamed.takeBytes()), payload)}',
  );

  _dictionaryExample();
}

void _dictionaryExample() {
  final samples = [
    for (var i = 0; i < 400; i++)
      utf8.encode('{"user":$i,"role":"editor","active":true,"team":"core"}'),
  ];

  final dictionary = ZstdDictionary.train(samples, maxSize: 4096);
  print(
    'trained ${dictionary.bytes.length} byte dictionary, '
    'id ${dictionary.id}',
  );

  final compressionDictionary = dictionary.prepareForCompression(level: 10);
  final decompressionDictionary = dictionary.prepareForDecompression();
  try {
    final codec = ZstdCodec(
      compressionDictionary: compressionDictionary,
      decompressionDictionary: decompressionDictionary,
    );
    final record = samples.first;
    final withDictionary = codec.encode(record);
    final without = zstd.encode(record);
    print(
      'single record: ${record.length} raw, ${without.length} plain, '
      '${withDictionary.length} with dictionary',
    );
    print(
      'dictionary round trip: '
      '${_same(codec.decode(withDictionary), record)}',
    );
  } finally {
    compressionDictionary.close();
    decompressionDictionary.close();
  }
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
