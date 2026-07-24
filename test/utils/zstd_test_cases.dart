import 'dart:convert';
import 'dart:typed_data';

/// A payload plus the level it should survive a round trip at.
typedef RoundTripCase = ({String description, List<int> payload, int level});

/// A payload split into [chunkSize] pieces before being streamed.
typedef ChunkedCase = ({String description, List<int> payload, int chunkSize});

/// Input that must be rejected, and the message fragment that says why.
typedef RejectionCase = ({String description, List<int> input, String reason});

final _repetitive = utf8.encode('the quick brown fox ' * 5000);
final _text = utf8.encode(
  List.generate(2000, (i) => 'line $i: some mostly english words\n').join(),
);

/// Deterministic bytes that zstd cannot shrink, so the encoder has to fall back
/// to storing them.
final _incompressible = Uint8List.fromList(
  List.generate(64 * 1024, (i) => (i * 2654435761) & 0xff),
);

final roundTripCases = <RoundTripCase>[
  (description: 'empty', payload: const <int>[], level: 0),
  (description: 'single byte', payload: const <int>[42], level: 0),
  (description: 'repetitive at default level', payload: _repetitive, level: 0),
  (description: 'repetitive at fastest level', payload: _repetitive, level: -5),
  (description: 'repetitive at densest level', payload: _repetitive, level: 19),
  (description: 'text at level 3', payload: _text, level: 3),
  (description: 'text at level 12', payload: _text, level: 12),
  (description: 'incompressible bytes', payload: _incompressible, level: 0),
  (
    description: 'larger than one zstd block',
    payload: _incompressible,
    level: 9,
  ),
];

final chunkedCases = <ChunkedCase>[
  (description: 'one byte at a time', payload: _text, chunkSize: 1),
  (description: 'odd chunks', payload: _text, chunkSize: 7),
  (
    description: 'chunks smaller than a block',
    payload: _repetitive,
    chunkSize: 1000,
  ),
  (
    description: 'chunks larger than a block',
    payload: _repetitive,
    chunkSize: 200 * 1024,
  ),
  (
    description: 'incompressible in small chunks',
    payload: _incompressible,
    chunkSize: 333,
  ),
];

final rejectionCases = <RejectionCase>[
  (
    description: 'truncated frame',
    input: const <int>[0x28, 0xb5, 0x2f, 0xfd, 0x24, 0x00],
    reason: 'middle of a frame',
  ),
  (
    description: 'not a frame at all',
    input: const <int>[1, 2, 3, 4, 5, 6, 7, 8],
    reason: 'Unknown frame descriptor',
  ),
];

/// Records that share enough structure for a dictionary to pay off.
final dictionarySamples = <List<int>>[
  for (var i = 0; i < 512; i++)
    utf8.encode(
      '{"id":$i,"role":"editor","active":true,"team":"core","region":"eu"}',
    ),
];
