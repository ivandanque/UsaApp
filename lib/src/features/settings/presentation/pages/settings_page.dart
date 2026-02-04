import 'package:flutter/material.dart';

import '../controllers/settings_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  static const routeName = '/settings';

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final SettingsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SettingsController();
    _controller.refreshStatus();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          Text(
            'P2P Connection Setup',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Column(
                children: [
                  // Permissions Card
                  Card(
                    child: ListTile(
                      leading: Icon(
                        _controller.allPermissionsGranted
                            ? Icons.check_circle
                            : Icons.warning_amber,
                        color: _controller.allPermissionsGranted
                            ? Colors.green
                            : Colors.orange,
                      ),
                      title: const Text('Permissions'),
                      subtitle: Text(
                        _controller.allPermissionsGranted
                            ? 'All permissions granted'
                            : 'Permissions needed for P2P functionality',
                      ),
                      trailing: _controller.isCheckingPermissions
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : ElevatedButton(
                              onPressed: _controller.setupPermissions,
                              child: const Text('Setup'),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Services Card
                  Card(
                    child: ListTile(
                      leading: Icon(
                        _controller.allServicesEnabled
                            ? Icons.check_circle
                            : Icons.warning_amber,
                        color: _controller.allServicesEnabled
                            ? Colors.green
                            : Colors.orange,
                      ),
                      title: const Text('Services'),
                      subtitle: Text(
                        _controller.allServicesEnabled
                            ? 'All services enabled'
                            : 'Wi-Fi, Location, and Bluetooth required',
                      ),
                      trailing: _controller.isCheckingServices
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : ElevatedButton(
                              onPressed: _controller.setupServices,
                              child: const Text('Setup'),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Overall Status
                  if (_controller.isP2pReady)
                    Card(
                      color: Colors.green.shade50,
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'P2P is ready! You can now discover and connect to nearby devices.',
                                style: TextStyle(color: Colors.green),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Device ID'),
              subtitle: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return SelectableText(_controller.deviceCode);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Background scanning preferences
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Column(
                children: [
                  Card(
                    child: SwitchListTile(
                      title: const Text('Background scanning'),
                      subtitle: const Text(
                        'Allow the app to scan and notify about nearby rooms when backgrounded',
                      ),
                      value: _controller.backgroundScanningEnabled,
                      onChanged: (bool v) => _controller.setBackgroundScanningEnabled(v),
                    ),
                  ),
                  if (_controller.backgroundScanningEnabled)
                    Card(
                      child: ListTile(
                        title: const Text('Scan cadence (seconds)'),
                        subtitle: Text('Every ${_controller.scanCadenceSeconds} second(s)'),
                        trailing: SizedBox(
                          width: 120,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove),
                                onPressed: () => _controller.setScanCadenceSeconds(_controller.scanCadenceSeconds - 1),
                              ),
                              Text('${_controller.scanCadenceSeconds}'),
                              IconButton(
                                icon: const Icon(Icons.add),
                                onPressed: () => _controller.setScanCadenceSeconds(_controller.scanCadenceSeconds + 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

