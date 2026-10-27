// cspell:words aarch64 androideabi buildmode cgo CFLAGS dylib dynamiclib ffi GOARM headerpad iphoneos iphonesimulator isysroot ldflags lresolv mios miphoneos ndk rpath SDKROOT sysroot trimpath tsnetbridge

/// Compiles the embedded tailnet library the iOS and Android app loads (#1881).
///
/// Android is a Go c-shared library. iOS is a Go c-archive relinked into a
/// dynamic library, which is what Flutter bundles. Every other target gets
/// [stub.c] so a desktop build can link without pulling in the tailnet.
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

const _name = 'tsnetbridge';
const _asset = 'services/embedded_tunnel_io.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    final out = input.outputDirectory.resolve(
      code.targetOS.dylibFileName(_name),
    );
    await Directory.fromUri(input.outputDirectory).create(recursive: true);

    if (code.targetOS == OS.android || code.targetOS == OS.iOS) {
      await _buildGo(input, code, out);
    } else {
      await _buildStub(input, code, out);
    }
    if (!File.fromUri(out).existsSync()) {
      throw StateError('The tailnet library was not written to $out.');
    }

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: _asset,
        linkMode: DynamicLoadingBundled(),
        file: out,
      ),
    );
    for (final relative in const [
      'cmd/tsnetbridge/bridge.go',
      'cmd/tsnetbridge/export.go',
      'cmd/tsnetbridge/main.go',
      'cmd/tsnetbridge/proxy.go',
      'go.mod',
      'go.sum',
      'hook/build.dart',
      'hook/stub.c',
    ]) {
      output.dependencies.add(_file(input, relative));
    }
  });
}

/// Go arguments shared by the Android and iOS builds. `ts_omit_logtail`
/// compiles out the networking library's diagnostic log uploader, so a phone
/// has no path that sends those logs to the vendor (#3786).
List<String> _goBuildArgs(String buildMode, String out) => [
  'build',
  '-trimpath',
  '-ldflags',
  '-s -w',
  '-tags',
  'ts_omit_logtail',
  '-buildmode',
  buildMode,
  '-o',
  out,
  './cmd/tsnetbridge',
];

/// Joins the tailnet. Fails with a fix when Go or the mobile toolchain is
/// missing, because a silent "not found" does not say what to install.
Future<void> _buildGo(HookInput input, CodeConfig code, Uri out) async {
  final go = _requireGo();
  final root = _rootPath(input);
  if (code.targetOS == OS.android) {
    final compiler = _compiler(
      code,
      'The Android NDK clang was not provided. Install the NDK; Flutter does '
      'that with the Android SDK.',
    );
    final api = code.android.targetNdkApi;
    final triple = _androidTriple(code.targetArchitecture);
    final target = '--target=$triple$api';
    await _run(
      go,
      _goBuildArgs('c-shared', out.toFilePath()),
      workingDirectory: root,
      environment: {
        'CGO_ENABLED': '1',
        'GOOS': 'android',
        'GOARCH': _goArch(code.targetArchitecture),
        if (code.targetArchitecture == Architecture.arm) 'GOARM': '7',
        'CC': compiler,
        'CGO_CFLAGS': '$target -fPIC -O2',
        'CGO_LDFLAGS': target,
      },
    );
    return;
  }

  final sdk = code.iOS.targetSdk.type;
  final sdkPath = await _xcrun(['--sdk', sdk, '--show-sdk-path']);
  final arch = _clangArch(code.targetArchitecture);
  final min = sdk == IOSSdk.iPhoneSimulator.type
      ? '-mios-simulator-version-min=${code.iOS.targetVersion}.0'
      : '-miphoneos-version-min=${code.iOS.targetVersion}.0';
  final flags = '-arch $arch -isysroot $sdkPath $min';
  final compiler =
      code.cCompiler?.compiler.toFilePath() ??
      await _xcrun(['--sdk', sdk, '--find', 'clang']);
  final archive = input.outputDirectory.resolve('lib$_name.a');
  await _run(
    go,
    _goBuildArgs('c-archive', archive.toFilePath()),
    workingDirectory: root,
    environment: {
      'CGO_ENABLED': '1',
      'GOOS': 'ios',
      'GOARCH': _goArch(code.targetArchitecture),
      'CC': compiler,
      'CGO_CFLAGS': flags,
      'CGO_LDFLAGS': flags,
    },
  );
  await _run(compiler, [
    '-dynamiclib',
    '-arch',
    arch,
    '-isysroot',
    sdkPath,
    min,
    '-Wl,-all_load',
    archive.toFilePath(),
    '-framework',
    'CoreFoundation',
    '-framework',
    'Security',
    '-framework',
    'Foundation',
    '-lresolv',
    '-install_name',
    '@rpath/${code.targetOS.dylibFileName(_name)}',
    '-Wl,-headerpad_max_install_names',
    '-o',
    out.toFilePath(),
  ]);
}

/// A desktop stand-in. It does not join a tailnet.
Future<void> _buildStub(HookInput input, CodeConfig code, Uri out) async {
  final compiler =
      code.cCompiler?.compiler.toFilePath() ??
      _findOnPath('cc') ??
      _findOnPath('gcc');
  if (compiler == null) {
    throw StateError(
      'No C compiler for the desktop tailnet stub. Install gcc or clang.',
    );
  }
  // Xcode's toolchain clang has no default SDK, and the hook runner drops
  // SDKROOT, so a macOS build names the SDK itself.
  final shared = code.targetOS == OS.macOS
      ? [
          '-dynamiclib',
          '-isysroot',
          await _xcrun(const ['--show-sdk-path']),
        ]
      : const ['-shared', '-fPIC'];
  await _run(compiler, [
    ...shared,
    '-o',
    out.toFilePath(),
    _file(input, 'hook/stub.c').toFilePath(),
  ]);
}

String _requireGo() {
  final found =
      _findOnPath('go') ??
      _firstExisting(const ['/usr/local/go/bin/go', '/opt/homebrew/bin/go']);
  if (found != null) return found;
  throw StateError(
    'Go is required to build the embedded tailnet for iOS and Android. '
    'Install Go and put it on PATH.',
  );
}

String _compiler(CodeConfig code, String missing) {
  final compiler = code.cCompiler?.compiler.toFilePath();
  if (compiler == null || compiler.isEmpty) throw StateError(missing);
  return compiler;
}

Future<String> _xcrun(List<String> args) async {
  final result = await Process.run('xcrun', args);
  if (result.exitCode != 0) {
    throw StateError(
      'xcrun ${args.join(' ')} failed. Install Xcode command line tools.\n'
      '${result.stderr}',
    );
  }
  return (result.stdout as String).trim();
}

Future<void> _run(
  String executable,
  List<String> args, {
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  final result = await Process.run(
    executable,
    args,
    workingDirectory: workingDirectory,
    environment: environment == null
        ? null
        : {...Platform.environment, ...environment},
  );
  if (result.exitCode != 0) {
    throw StateError(
      '$executable ${args.join(' ')} failed (${result.exitCode}).\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
}

String _goArch(Architecture arch) {
  if (arch == Architecture.arm64 || arch == Architecture.arm64e) return 'arm64';
  if (arch == Architecture.arm) return 'arm';
  if (arch == Architecture.x64) return 'amd64';
  if (arch == Architecture.ia32) return '386';
  if (arch == Architecture.riscv64) return 'riscv64';
  throw UnsupportedError('No Go architecture for ${arch.name}.');
}

String _clangArch(Architecture arch) {
  if (arch == Architecture.arm64) return 'arm64';
  if (arch == Architecture.arm64e) return 'arm64e';
  if (arch == Architecture.x64) return 'x86_64';
  throw UnsupportedError('No iOS architecture for ${arch.name}.');
}

String _androidTriple(Architecture arch) {
  if (arch == Architecture.arm64) return 'aarch64-linux-android';
  if (arch == Architecture.arm) return 'armv7a-linux-androideabi';
  if (arch == Architecture.x64) return 'x86_64-linux-android';
  if (arch == Architecture.ia32) return 'i686-linux-android';
  if (arch == Architecture.riscv64) return 'riscv64-linux-android';
  throw UnsupportedError('No Android architecture for ${arch.name}.');
}

Uri _file(HookInput input, String relative) {
  final root = input.packageRoot;
  final base = root.path.endsWith('/')
      ? root
      : root.replace(path: '${root.path}/');
  return base.resolve(relative);
}

String _rootPath(HookInput input) => _file(input, '').toFilePath();

String? _findOnPath(String name) {
  final path = Platform.environment['PATH'];
  if (path == null || path.isEmpty) return null;
  for (final dir in path.split(':')) {
    if (dir.isEmpty) continue;
    final candidate = '$dir/$name';
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

String? _firstExisting(List<String> paths) {
  for (final path in paths) {
    if (File(path).existsSync()) return path;
  }
  return null;
}
