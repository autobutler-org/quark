import 'package:flutter/material.dart';
import 'package:quark/controllers/tsnet_debug_controller.dart';
import 'package:quark_tsnet/quark_tsnet.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Debug-only screen for the #1881 spike: runs the embedded tsnet node and
/// shows whether the app can reach its Quark through the loopback proxy.
///
/// Reached from a Settings row that exists only when `kDebugMode`, and its
/// route is registered only then too. Throwaway: it lives on the spike branch.
///
/// Key prefixes: `tsnet_debug_` + `pair`, `start`, `stop`, `fetch`,
/// `control_url`, `auth_key`, `upstream`.
class TsnetDebugPage extends StatefulWidget {
  /// Creates the page.
  const TsnetDebugPage({super.key});

  @override
  State<TsnetDebugPage> createState() => _TsnetDebugPageState();
}

class _TsnetDebugPageState extends State<TsnetDebugPage> {
  final _c = TsnetDebugController()..attach();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Embedded tailnet (debug)')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _c,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!QuarkTsnet.isSupported)
                const Text('The embedded node needs a native build.'),
              OutlinedButton(
                key: const ValueKey('tsnet_debug_pair'),
                onPressed: _c.busy ? null : _c.pair,
                child: const Text('Pair with my Quark'),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('tsnet_debug_control_url'),
                controller: _c.controlUrl,
                decoration: const InputDecoration(labelText: 'Control URL'),
              ),
              TextField(
                key: const ValueKey('tsnet_debug_auth_key'),
                controller: _c.authKey,
                decoration: const InputDecoration(labelText: 'Auth key'),
              ),
              TextField(
                key: const ValueKey('tsnet_debug_upstream'),
                controller: _c.upstream,
                decoration: const InputDecoration(
                  labelText: 'Quark tailnet address (http://100.x.y.z)',
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    key: const ValueKey('tsnet_debug_start'),
                    onPressed: _c.busy || _c.status.isRunning ? null : _c.start,
                    child: const Text('Start'),
                  ),
                  OutlinedButton(
                    key: const ValueKey('tsnet_debug_stop'),
                    onPressed: _c.busy ? null : _c.stop,
                    child: const Text('Stop'),
                  ),
                  OutlinedButton(
                    key: const ValueKey('tsnet_debug_fetch'),
                    onPressed: _c.busy || !_c.status.isRunning
                        ? null
                        : _c.fetchVersion,
                    child: const Text('GET /api/v0/version'),
                  ),
                  if (_c.busy) const QuarkLoader(size: 20),
                ],
              ),
              const SizedBox(height: 16),
              if (_c.error != null)
                Text(
                  _c.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              SelectableText(
                'State: ${_c.status.state}\n'
                'Tailnet IPs: ${_c.status.tailnetIPs.join(', ')}\n'
                'Loopback URL: ${_c.status.loopbackUrl ?? '-'}\n'
                'Start took: ${_c.startTook?.inMilliseconds ?? '-'} ms',
              ),
              if (_c.versionResult != null) ...[
                const SizedBox(height: 16),
                SelectableText(_c.versionResult!),
              ],
              // The bridge's own diagnostic, for the developer running this
              // debug build; release builds never reach this page.
              if (_c.status.error.isNotEmpty) ...[
                const SizedBox(height: 16),
                SelectableText('Bridge diagnostic: ${_c.status.error}'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
