import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

// The package builds from the committed copy; the submodule is the upstream pin
// the update workflow tracks, and only a checkout without that copy falls back
// to it.
const _libCandidates = ['third_party/libzstd/lib', 'third_party/zstd/lib'];

void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    // MSVC cannot assemble the GNU-syntax decompression fast path, and needs
    // the export attribute spelled out for every public symbol.
    final windows = input.config.code.targetOS == OS.windows;

    final lib = _resolveLib(input.packageRoot);

    await CBuilder.library(
      name: 'zstd',
      assetName: 'src/bindings.g.dart',
      sources: [
        for (final directory in const [
          'common',
          'compress',
          'decompress',
          'dictBuilder',
        ])
          ..._csFiles(input.packageRoot, '$lib/$directory'),
        if (!windows) '$lib/decompress/huf_decompress_amd64.S',
      ],
      includes: [lib, '$lib/common'],
      defines: {
        'XXH_NAMESPACE': 'ZSTD_',
        'ZSTD_MULTITHREAD': '1',
        if (windows) 'ZSTD_DISABLE_ASM': '1',
        if (windows) 'ZSTD_DLL_EXPORT': '1',
      },
      std: 'c11',
    ).run(input: input, output: output);
  });
}

String _resolveLib(Uri packageRoot) {
  for (final candidate in _libCandidates) {
    if (File.fromUri(packageRoot.resolve('$candidate/zstd.h')).existsSync()) {
      return candidate;
    }
  }
  throw StateError(
    'libzstd sources not found in ${_libCandidates.join(' or ')}. '
    'Run `git submodule update --init` or restore third_party/libzstd.',
  );
}

/// Sorted so the compiler command line stays stable between runs.
List<String> _csFiles(Uri packageRoot, String directory) =>
    Directory.fromUri(packageRoot.resolve('$directory/'))
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .where((name) => name.endsWith('.c'))
        .map((name) => '$directory/$name')
        .toList()
      ..sort();
