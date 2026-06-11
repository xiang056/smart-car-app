import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// HM-10 BLE UART service / characteristic UUIDs
const String _kServiceUuid = 'FFE0';
const String _kCharUuid    = 'FFE1';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const SmartCarApp());
}

class SmartCarApp extends StatelessWidget {
  const SmartCarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Car',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        colorScheme: const ColorScheme.dark(
          primary: Colors.cyan,
          secondary: Colors.cyanAccent,
        ),
      ),
      home: const CarControlPage(),
    );
  }
}

class CarControlPage extends StatefulWidget {
  const CarControlPage({super.key});

  @override
  State<CarControlPage> createState() => _CarControlPageState();
}

class _CarControlPageState extends State<CarControlPage> {
  BluetoothDevice?          _device;
  BluetoothCharacteristic?  _txChar;
  bool                      _isConnected = false;
  String                    _status      = 'Disconnected';
  int                       _carState    = 0;   // mirrors CarState_t (0–8)
  int                       _speedPct    = 0;
  String                    _lastCmd     = 'S';

  StreamSubscription<List<int>>?                _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
    }
  }

  Future<void> _connect() async {
    await _requestPermissions();
    if (!mounted) return;

    final device = await showDialog<BluetoothDevice>(
      context: context,
      builder: (_) => const _BleScanDialog(),
    );
    if (device == null) return;

    try {
      setState(() => _status = 'Connecting...');
      await device.connect(timeout: const Duration(seconds: 10));

      _connSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && mounted) {
          _notifySub?.cancel();
          _lastCmd = '';
          setState(() {
            _isConnected = false;
            _status      = 'Disconnected';
            _carState    = 0;
            _speedPct    = 0;
            _txChar      = null;
          });
        }
      });

      final services = await device.discoverServices();
      BluetoothCharacteristic? char;
      outer:
      for (final s in services) {
        if (s.uuid.toString().toUpperCase().contains(_kServiceUuid)) {
          for (final c in s.characteristics) {
            if (c.uuid.toString().toUpperCase().contains(_kCharUuid)) {
              char = c;
              break outer;
            }
          }
        }
      }

      if (char == null) {
        await device.disconnect();
        if (mounted) setState(() => _status = 'HM-10 UART service not found');
        return;
      }

      await char.setNotifyValue(true);
      _notifySub = char.onValueReceived.listen((data) {
        final text  = utf8.decode(data, allowMalformed: true);
        final match = RegExp(r'S,(\d+),(\d+)').firstMatch(text);
        if (match != null && mounted) {
          setState(() {
              _speedPct = int.tryParse(match.group(1)!) ?? 0;
              _carState = int.tryParse(match.group(2)!) ?? 0;
            });
        }
      });

      setState(() {
        _device      = device;
        _txChar      = char;
        _isConnected = true;
        final name   = device.platformName.isNotEmpty
            ? device.platformName
            : device.remoteId.toString();
        _status = 'Connected: $name';
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Connection failed');
    }
  }

  Future<void> _disconnect() async {
    await _notifySub?.cancel();
    await _connSub?.cancel();
    await _device?.disconnect();
    _lastCmd = '';
    if (mounted) {
      setState(() {
        _device      = null;
        _txChar      = null;
        _isConnected = false;
        _status      = 'Disconnected';
        _carState    = 0;
        _speedPct    = 0;
      });
    }
  }

  void _send(String cmd) {
    if (!_isConnected || _txChar == null) return;
    if (cmd == _lastCmd) return;
    _lastCmd = cmd;
    _txChar!.write(utf8.encode(cmd), withoutResponse: true).catchError((e) {
      if (mounted) setState(() => _status = 'Write error: $e');
    });
  }

  @override
  void dispose() {
    _notifySub?.cancel();
    _connSub?.cancel();
    _device?.disconnect();
    super.dispose();
  }

  static const _stateLabels = [
    'STOP',      // 0
    'FORWARD',   // 1
    'BACKWARD',  // 2
    'LEFT',      // 3
    'RIGHT',     // 4
    'FWD LEFT',  // 5
    'FWD RIGHT', // 6
    'BWD LEFT',  // 7
    'BWD RIGHT', // 8
  ];
  static const _stateIcons = [
    Icons.stop_circle_outlined,           // 0
    Icons.keyboard_arrow_up_rounded,      // 1
    Icons.keyboard_arrow_down_rounded,    // 2
    Icons.keyboard_arrow_left_rounded,    // 3
    Icons.keyboard_arrow_right_rounded,   // 4
    Icons.turn_slight_left,               // 5
    Icons.turn_slight_right,              // 6
    Icons.turn_slight_left,               // 7
    Icons.turn_slight_right,              // 8
  ];
  static const _stateColors = [
    Colors.white38,    // 0 STOP
    Colors.cyan,       // 1 FORWARD
    Colors.orange,     // 2 BACKWARD
    Colors.cyanAccent, // 3 LEFT
    Colors.cyanAccent, // 4 RIGHT
    Colors.cyan,       // 5 FWD LEFT
    Colors.cyan,       // 6 FWD RIGHT
    Colors.orange,     // 7 BWD LEFT
    Colors.orange,     // 8 BWD RIGHT
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Row(
          children: [
            Icon(Icons.directions_car, color: Colors.cyan, size: 22),
            SizedBox(width: 8),
            Text('Smart Car',
                style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: Icon(
                _isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                color: _isConnected ? Colors.cyan : Colors.white38,
              ),
              onPressed: _isConnected ? _disconnect : _connect,
              tooltip: _isConnected ? 'Disconnect' : 'Connect',
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _StatusBar(status: _status, isConnected: _isConnected),
              const SizedBox(height: 16),
              _StateCard(
                state:    _carState,
                label:    _stateLabels[_carState.clamp(0, 8)],
                icon:     _stateIcons[_carState.clamp(0, 8)],
                color:    _stateColors[_carState.clamp(0, 8)],
                speedPct: _speedPct,
              ),
              const SizedBox(height: 8),
              const Spacer(),
              _DPad(onSend: _send, enabled: _isConnected),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── BLE 掃描對話框 ──────────────────────────────────────────
class _BleScanDialog extends StatefulWidget {
  const _BleScanDialog();

  @override
  State<_BleScanDialog> createState() => _BleScanDialogState();
}

class _BleScanDialogState extends State<_BleScanDialog> {
  final Map<DeviceIdentifier, ScanResult> _results = {};
  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _results.clear();
    });

    await FlutterBluePlus.stopScan();

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          for (final r in results) {
            _results[r.device.remoteId] = r;
          }
        });
      }
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    if (mounted) setState(() => _scanning = false);
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devices = _results.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.bluetooth_searching, color: Colors.cyan, size: 22),
          const SizedBox(width: 8),
          const Text('Scan BLE', style: TextStyle(color: Colors.cyan)),
          const Spacer(),
          if (_scanning)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(color: Colors.cyan, strokeWidth: 2),
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: devices.isEmpty
            ? Center(
                child: Text(
                  _scanning ? 'Scanning...' : 'No devices found',
                  style: const TextStyle(color: Colors.white38),
                ),
              )
            : ListView.separated(
                itemCount: devices.length,
                separatorBuilder: (_, _) =>
                    const Divider(color: Colors.white12, height: 1),
                itemBuilder: (context, i) {
                  final r    = devices[i];
                  final name = r.device.platformName.isNotEmpty
                      ? r.device.platformName
                      : 'Unknown';
                  return ListTile(
                    leading: const Icon(Icons.bluetooth, color: Colors.cyan),
                    title: Text(name,
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text(
                      '${r.device.remoteId}  RSSI: ${r.rssi} dBm',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                    ),
                    onTap: () => Navigator.pop(context, r.device),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
        ),
        TextButton(
          onPressed: _scanning ? null : _startScan,
          child: const Text('Rescan', style: TextStyle(color: Colors.cyan)),
        ),
      ],
    );
  }
}

// ── UI 元件（不變）─────────────────────────────────────────
class _StatusBar extends StatelessWidget {
  final String status;
  final bool isConnected;

  const _StatusBar({required this.status, required this.isConnected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected ? Colors.greenAccent : Colors.red,
              boxShadow: isConnected
                  ? [BoxShadow(
                      color: Colors.greenAccent.withValues(alpha: 0.6),
                      blurRadius: 6)]
                  : [],
            ),
          ),
          const SizedBox(width: 10),
          Text(status,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  final int     state;
  final String  label;
  final IconData icon;
  final Color   color;
  final int     speedPct;

  const _StateCard({
    required this.state,
    required this.label,
    required this.icon,
    required this.color,
    required this.speedPct,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        children: [
          const Text(
            'STATUS',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Icon(icon, color: color, size: 36),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '$speedPct%',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: speedPct / 100,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 6,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DPad extends StatelessWidget {
  final void Function(String) onSend;
  final bool enabled;

  const _DPad({required this.onSend, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CarButton(
          icon: Icons.keyboard_arrow_up_rounded,
          label: 'FORWARD',
          cmd: 'F',
          onSend: onSend,
          enabled: enabled,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CarButton(
              icon: Icons.keyboard_arrow_left_rounded,
              label: 'LEFT',
              cmd: 'L',
              onSend: onSend,
              enabled: enabled,
            ),
            const SizedBox(width: 10),
            _StopButton(onTap: () => onSend('S'), enabled: enabled),
            const SizedBox(width: 10),
            _CarButton(
              icon: Icons.keyboard_arrow_right_rounded,
              label: 'RIGHT',
              cmd: 'R',
              onSend: onSend,
              enabled: enabled,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _CarButton(
          icon: Icons.keyboard_arrow_down_rounded,
          label: 'BACK',
          cmd: 'B',
          onSend: onSend,
          enabled: enabled,
        ),
      ],
    );
  }
}

class _CarButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String cmd;
  final void Function(String) onSend;
  final bool enabled;

  const _CarButton({
    required this.icon,
    required this.label,
    required this.cmd,
    required this.onSend,
    required this.enabled,
  });

  @override
  State<_CarButton> createState() => _CarButtonState();
}

class _CarButtonState extends State<_CarButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && _pressed;
    return GestureDetector(
      onTapDown: (_) {
        if (!widget.enabled) return;
        setState(() => _pressed = true);
        widget.onSend(widget.cmd);
      },
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onSend('S');
      },
      onTapCancel: () {
        setState(() => _pressed = false);
        widget.onSend('S');
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: active ? Colors.cyan : const Color(0xFF222222),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: widget.enabled
                ? (active ? Colors.cyan : Colors.cyan.withValues(alpha: 0.35))
                : Colors.white12,
            width: 2,
          ),
          boxShadow: active
              ? [BoxShadow(
                  color: Colors.cyan.withValues(alpha: 0.45),
                  blurRadius: 16,
                  spreadRadius: 2)]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.icon,
              size: 38,
              color: active
                  ? Colors.black
                  : (widget.enabled ? Colors.cyan : Colors.white24),
            ),
            const SizedBox(height: 2),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1,
                fontWeight: FontWeight.w600,
                color: active
                    ? Colors.black87
                    : (widget.enabled ? Colors.white54 : Colors.white24),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StopButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool enabled;

  const _StopButton({required this.onTap, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: enabled
              ? Colors.red.withValues(alpha: 0.12)
              : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: enabled ? Colors.red : Colors.white12,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.stop_circle_outlined,
                size: 38,
                color: enabled ? Colors.red : Colors.white24),
            const SizedBox(height: 2),
            Text(
              'STOP',
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
                color: enabled ? Colors.red : Colors.white24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
