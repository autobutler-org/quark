/// Native-assets build hook: compiles the Go bridge in `go/` for the target
/// OS and architecture and hands Flutter the resulting dynamic library.
///
/// Go builds `-buildmode=c-shared` everywhere it can. iOS has no Go c-shared
/// mode and Flutter's native assets bundle dynamic libraries only, so on iOS
/// the hook builds `-buildmode=c-archive` and relinks the archive into a
/// dylib with clang; Flutter then wraps it in a framework.
///
/// Needs Go on PATH (or at /usr/local/go/bin, /opt/homebrew/bin) and, through
/// cgo, the C compiler Flutter passes in: Xcode's clang for Apple targets, the
/// NDK's clang for Android.
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

const _libName = 'quark_tsnet';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    final goDir = input.packageRoot.resolve('go/');
    final outFile = input.outputDirectory.resolve(
      code.targetOS.dylibFileName(_libName),
    );

    final env = <String, String>{
      'CGO_ENABLED': '1',
      'GOOS': _goos(code),
      'GOARCH': _goarch(code.targetArchitecture),
    };
    final cc = code.cCompiler?.compiler.toFilePath();
    if (cc != null) env['CC'] = cc;
    final cflags = <String>[];
    String? sysroot;
    String? appleTarget;

    switch (code.targetOS) {
      case OS.android:
        final triple = switch (code.targetArchitecture) {
          Architecture.arm64 => 'aarch64-linux-android',
          Architecture.x64 => 'x86_64-linux-android',
          Architecture.arm => 'armv7a-linux-androideabi',
          Architecture.ia32 => 'i686-linux-android',
          final a => throw UnsupportedError('Android $a'),
        };
        cflags.add('--target=$triple${code.android.targetNdkApi}');
      case OS.iOS:
        final simulator = code.iOS.targetSdk == IOSSdk.iPhoneSimulator;
        final sdk = simulator ? 'iphonesimulator' : 'iphoneos';
        sysroot = await _run('xcrun', ['--sdk', sdk, '--show-sdk-path']);
        env['CC'] ??= await _run('xcrun', ['--sdk', sdk, '-f', 'clang']);
        final arch = code.targetArchitecture == Architecture.x64
            ? 'x86_64'
            : 'arm64';
        appleTarget =
            '$arch-apple-ios${code.iOS.targetVersion}.0'
            '${simulator ? '-simulator' : ''}';
        cflags.addAll(['-isysroot', sysroot, '-target', appleTarget]);
      case OS.macOS:
        // Flutter hands over the toolchain clang, which has no default SDK.
        final sdk = await _run('xcrun', ['--sdk', 'macosx', '--show-sdk-path']);
        cflags.addAll([
          '-isysroot',
          sdk,
          '-mmacosx-version-min=${code.macOS.targetVersion}.0',
        ]);
      default:
    }
    // Flutter and dart rewrite the dylib's install name when bundling, which
    // needs header room the default Apple link does not leave.
    const headerpad = '-Wl,-headerpad_max_install_names';
    final isApple = code.targetOS == OS.iOS || code.targetOS == OS.macOS;
    env['CGO_CFLAGS'] = cflags.join(' ');
    env['CGO_LDFLAGS'] = [...cflags, if (isApple) headerpad].join(' ');

    final isIOS = code.targetOS == OS.iOS;
    final goOut = isIOS
        ? input.outputDirectory.resolve('lib$_libName.a').toFilePath()
        : outFile.toFilePath();
    await _run(
      await _findGo(),
      [
        'build',
        '-trimpath',
        '-ldflags=-s -w',
        '-buildmode=${isIOS ? 'c-archive' : 'c-shared'}',
        '-o',
        goOut,
        '.',
      ],
      workingDirectory: goDir.toFilePath(),
      environment: env,
    );

    if (isIOS) {
      await _run(env['CC']!, [
        '-target', appleTarget!, '-isysroot', sysroot!, //
        '-dynamiclib', '-Wl,-all_load', goOut,
        '-framework', 'CoreFoundation', '-framework', 'Security',
        '-install_name', '@rpath/${code.targetOS.dylibFileName(_libName)}',
        headerpad, '-Wl,-x', '-o', outFile.toFilePath(),
      ]);
    }

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/bridge_ffi.dart',
        linkMode: DynamicLoadingBundled(),
        file: outFile,
      ),
    );
    await for (final f in Directory.fromUri(goDir).list(recursive: true)) {
      if (f is File && !f.path.endsWith('_test.go')) {
        output.dependencies.add(f.uri);
      }
    }
  });
}

String _goos(CodeConfig code) => switch (code.targetOS) {
  OS.android => 'android',
  OS.iOS => 'ios',
  OS.macOS => 'darwin',
  OS.linux => 'linux',
  OS.windows => 'windows',
  final os => throw UnsupportedError('quark_tsnet does not build for $os'),
};

String _goarch(Architecture a) => switch (a) {
  Architecture.arm64 => 'arm64',
  Architecture.x64 => 'amd64',
  Architecture.arm => 'arm',
  Architecture.ia32 => '386',
  Architecture.riscv64 => 'riscv64',
  _ => throw UnsupportedError('quark_tsnet does not build for $a'),
};

/// Finds `go`: on PATH first, then where the official and Homebrew installers
/// put it (an Xcode build phase can run with a bare PATH).
Future<String> _findGo() async {
  final which = await Process.run('which', ['go']);
  if (which.exitCode == 0) return (which.stdout as String).trim();
  for (final p in ['/usr/local/go/bin/go', '/opt/homebrew/bin/go']) {
    if (File(p).existsSync()) return p;
  }
  throw StateError(
    'quark_tsnet needs Go to build its native library. Install Go '
    '(https://go.dev/dl, same version as the root go.mod) and put it on PATH.',
  );
}

Future<String> _run(
  String exe,
  List<String> args, {
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  final r = await Process.run(
    exe,
    args,
    workingDirectory: workingDirectory,
    environment: environment,
  );
  if (r.exitCode != 0) {
    throw ProcessException(
      exe,
      args,
      'exit ${r.exitCode}\n${r.stdout}\n${r.stderr}',
      r.exitCode,
    );
  }
  return (r.stdout as String).trim();
}
