import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const int serverPort = 5000;
const String dataPath = '/data';
const Duration refreshInterval = Duration(seconds: 5);
const int maxHistory = 60;

void main() => runApp(const SmartRoomApp());

class SmartRoomApp extends StatelessWidget {
  const SmartRoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Room Monitor',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.teal,
      ),
      home: const HomePage(),
    );
  }
}

// ---------------- Data ----------------

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.parse(v);
  throw FormatException('Not a number: $v');
}

/// Comfort is computed in the app, since the server only sends raw values.
String computeComfort(double temp, double humidity) {
  if (temp < 20) return 'too_cold';
  if (temp > 24) return 'too_warm';
  if (humidity > 60) return 'too_humid';
  if (humidity < 30) return 'too_dry';
  return 'comfortable';
}

class Reading {
  final DateTime timestamp;
  final double temperature;
  final double humidity;
  final double pressure;

  Reading({
    required this.timestamp,
    required this.temperature,
    required this.humidity,
    required this.pressure,
  });

  String get comfort => computeComfort(temperature, humidity);

  /// Server JSON: {"temperature": .., "humidity": .., "air-pressure": ..}
  factory Reading.fromJson(Map<String, dynamic> j) => Reading(
        timestamp: DateTime.now(),
        temperature: _toDouble(j['temperature']),
        humidity: _toDouble(j['humidity']),
        pressure: _toDouble(j['air-pressure']),
      );
}

class Api {
  /// Cleans user input like "http://192.168.0.102:5000/data " down to
  /// "192.168.0.102". Returns null if it isn't a usable host.
  static String? normalizeHost(String input) {
    final h = input
        .trim()
        .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
        .replaceAll(RegExp(r'/.*$'), '')
        .replaceFirst(RegExp(r':\d*$'), '');
    if (h.isEmpty || !RegExp(r'^[A-Za-z0-9.\-]+$').hasMatch(h)) return null;
    return h;
  }

  /// IP + ":5000/data"
  static String dataUrl(String host) => 'http://$host:$serverPort$dataPath';

  static Future<Reading> fetch(String url) async {
    final res = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 4));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return Reading.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }
}

// ---------------- Comfort levels ----------------

class ComfortInfo {
  final String label;
  final String advice;
  final IconData icon;
  final List<Color> colors;
  const ComfortInfo(this.label, this.advice, this.icon, this.colors);
}

ComfortInfo comfortInfo(String level) {
  switch (level) {
    case 'comfortable':
      return const ComfortInfo('Comfortable',
          'Conditions are ideal. No heating or ventilation needed.',
          Icons.sentiment_satisfied_alt, [Color(0xFF11998E), Color(0xFF38EF7D)]);
    case 'too_cold':
      return const ComfortInfo('Too cold',
          'Consider raising the heating slightly.',
          Icons.ac_unit, [Color(0xFF2193B0), Color(0xFF6DD5ED)]);
    case 'too_warm':
      return const ComfortInfo('Too warm',
          'Lower the heating before opening windows to save energy.',
          Icons.wb_sunny, [Color(0xFFF7971E), Color(0xFFFFD200)]);
    case 'too_humid':
      return const ComfortInfo('Too humid',
          'A short burst of ventilation will bring humidity down.',
          Icons.water_drop, [Color(0xFF7F00FF), Color(0xFFE100FF)]);
    case 'too_dry':
      return const ComfortInfo('Too dry',
          'Avoid over-ventilating — the air is already dry.',
          Icons.grain, [Color(0xFFDA4453), Color(0xFF89216B)]);
    default:
      return const ComfortInfo('Unknown', 'Waiting for data…',
          Icons.help_outline, [Color(0xFF606C88), Color(0xFF3F4C6B)]);
  }
}

// ---------------- Home page ----------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _host;
  Reading? _latest;
  final List<Reading> _history = [];
  bool _online = false;
  bool _loading = false;
  String? _error;
  Timer? _timer;

  bool _fetching = false;
  int _generation = 0; // ignores responses from a previous IP

  // Rooms the user has added. All rooms show the same data for now.
  final List<String> _rooms = ['Living room'];
  String _selectedRoom = 'Living room';

  String? get _url => _host == null ? null : Api.dataUrl(_host!);

  @override
  void initState() {
    super.initState();
    // Ask for the IP right away on first launch.
    WidgetsBinding.instance.addPostFrameCallback((_) => _editIp());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _editIp() async {
    final host = await showDialog<String>(
      context: context,
      builder: (_) => IpDialog(initial: _host ?? ''),
    );
    if (host != null && mounted) _connect(host);
  }

  void _connect(String host) {
    _timer?.cancel();
    _generation++;
    _fetching = false;
    setState(() {
      _host = host;
      _latest = null;
      _history.clear();
      _online = false;
      _loading = true;
      _error = null;
    });
    _load();
    _timer = Timer.periodic(refreshInterval, (_) => _load());
  }

  Future<void> _load() async {
    final url = _url;
    if (url == null || _fetching) return;
    _fetching = true;
    final gen = _generation;
    try {
      final reading = await Api.fetch(url);
      if (!mounted || gen != _generation) return;
      setState(() {
        _latest = reading;
        _history.add(reading);
        if (_history.length > maxHistory) _history.removeAt(0);
        _online = true;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _online = false;
        _loading = false;
        _error = e.toString();
      });
    } finally {
      if (gen == _generation) _fetching = false;
    }
  }

  Future<void> _addRoom() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add room'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Bedroom'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final room = name?.trim() ?? '';
    if (room.isEmpty) return;

    final existing = _rooms.where((r) => r.toLowerCase() == room.toLowerCase());
    if (existing.isNotEmpty) {
      setState(() => _selectedRoom = existing.first);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${existing.first}" already exists')),
      );
      return;
    }
    setState(() {
      _rooms.add(room);
      _selectedRoom = room;
    });
  }

  @override
  Widget build(BuildContext context) {
    final latest = _latest;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _Header(
                  latest: latest,
                  online: _online,
                  host: _host,
                  rooms: _rooms,
                  selectedRoom: _selectedRoom,
                  onRoomSelected: (r) => setState(() => _selectedRoom = r),
                  onAddRoom: _addRoom,
                  onEditIp: _editIp,
                ),
                const SizedBox(height: 20),
                if (_host == null)
                  _SetupView(onEnterIp: _editIp)
                else if (_loading)
                  const SizedBox(
                      height: 300,
                      child: Center(child: CircularProgressIndicator()))
                else if (latest == null)
                  _OfflineView(
                    url: _url!,
                    error: _error,
                    onRetry: _load,
                    onChangeIp: _editIp,
                  )
                else ...[
                  if (!_online) const _Banner('Offline — showing last data'),
                  _ComfortCard(info: comfortInfo(latest.comfort)),
                  const SizedBox(height: 16),
                  MetricCard(
                    large: true,
                    icon: Icons.thermostat,
                    label: 'Temperature',
                    value: latest.temperature.toStringAsFixed(1),
                    unit: '°C',
                    color: const Color(0xFFFF8A65),
                    values: _history.map((r) => r.temperature).toList(),
                    footnote: 'Comfort range 20–24 °C',
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: MetricCard(
                          icon: Icons.water_drop_outlined,
                          label: 'Humidity',
                          value: latest.humidity.toStringAsFixed(0),
                          unit: '%',
                          color: const Color(0xFF4FC3F7),
                          values: _history.map((r) => r.humidity).toList(),
                          footnote: 'Ideal 30–60 %',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: MetricCard(
                          icon: Icons.speed,
                          label: 'Pressure',
                          value: latest.pressure.toStringAsFixed(0),
                          unit: 'hPa',
                          color: const Color(0xFFBA68C8),
                          values: _history.map((r) => r.pressure).toList(),
                          footnote: 'Air pressure',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'Trends show the last ${_history.length} readings',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _time(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

// ---------------- IP dialog ----------------

class IpDialog extends StatefulWidget {
  final String initial;
  const IpDialog({super.key, required this.initial});

  @override
  State<IpDialog> createState() => _IpDialogState();
}

class _IpDialogState extends State<IpDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final host = Api.normalizeHost(_controller.text);
    if (host == null) {
      setState(() => _error = 'Enter a valid IP, e.g. 192.168.0.102');
      return;
    }
    Navigator.pop(context, host);
  }

  @override
  Widget build(BuildContext context) {
    final preview = Api.normalizeHost(_controller.text);
    return AlertDialog(
      title: const Text('Raspberry Pi IP address'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: '192.168.0.102',
              prefixIcon: const Icon(Icons.router_outlined),
              errorText: _error,
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          Text(
            preview == null ? ' ' : 'Will fetch: ${Api.dataUrl(preview)}',
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Connect')),
      ],
    );
  }
}

// ---------------- Widgets ----------------

class _Header extends StatelessWidget {
  final Reading? latest;
  final bool online;
  final String? host;
  final List<String> rooms;
  final String selectedRoom;
  final ValueChanged<String> onRoomSelected;
  final VoidCallback onAddRoom;
  final VoidCallback onEditIp;

  const _Header({
    required this.latest,
    required this.online,
    required this.host,
    required this.rooms,
    required this.selectedRoom,
    required this.onRoomSelected,
    required this.onAddRoom,
    required this.onEditIp,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Smart Home Agent',
                  style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ),
            _StatusPill(online: online),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            RoomSelector(
              rooms: rooms,
              selected: selectedRoom,
              onSelected: onRoomSelected,
              onAdd: onAddRoom,
            ),
            _IpChip(host: host, onTap: onEditIp),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          host == null
              ? 'No device set'
              : latest == null
                  ? 'Connecting…'
                  : 'Updated ${_time(latest!.timestamp)}',
          style: const TextStyle(color: Colors.white60),
        ),
      ],
    );
  }
}

class _IpChip extends StatelessWidget {
  final String? host;
  final VoidCallback onTap;
  const _IpChip({required this.host, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.router_outlined, size: 18, color: Colors.white70),
            const SizedBox(width: 8),
            Text(host ?? 'Set IP',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
            const SizedBox(width: 6),
            const Icon(Icons.edit, size: 16, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

const String _addRoomKey = '__add_room__';

class RoomSelector extends StatelessWidget {
  final List<String> rooms;
  final String selected;
  final ValueChanged<String> onSelected;
  final VoidCallback onAdd;

  const RoomSelector({
    super.key,
    required this.rooms,
    required this.selected,
    required this.onSelected,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Choose room',
      color: const Color(0xFF203A43),
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (v) => v == _addRoomKey ? onAdd() : onSelected(v),
      itemBuilder: (_) => [
        for (final room in rooms)
          PopupMenuItem(
            value: room,
            child: Row(
              children: [
                Icon(
                  room == selected
                      ? Icons.check_circle
                      : Icons.meeting_room_outlined,
                  size: 20,
                  color: room == selected ? Colors.tealAccent : Colors.white54,
                ),
                const SizedBox(width: 12),
                Text(room, style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _addRoomKey,
          child: Row(
            children: [
              Icon(Icons.add, size: 20, color: Colors.tealAccent),
              SizedBox(width: 12),
              Text('Add room', style: TextStyle(color: Colors.tealAccent)),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.meeting_room, size: 18, color: Colors.white70),
            const SizedBox(width: 8),
            Text(selected,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool online;
  const _StatusPill({required this.online});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(Icons.circle,
              size: 10, color: online ? Colors.greenAccent : Colors.redAccent),
          const SizedBox(width: 6),
          Text(online ? 'Live' : 'Offline',
              style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _ComfortCard extends StatelessWidget {
  final ComfortInfo info;
  const _ComfortCard({required this.info});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: info.colors),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: info.colors.first.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(info.icon, size: 56, color: Colors.white),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ROOM COMFORT',
                    style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 1.5,
                        color: Colors.white70)),
                const SizedBox(height: 4),
                Text(info.label,
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 6),
                Text(info.advice, style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color color;
  final List<double> values;
  final String footnote;
  final bool large;

  const MetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.values,
    required this.footnote,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: large ? 56 : 34,
                      fontWeight: FontWeight.w300,
                      color: Colors.white)),
              const SizedBox(width: 4),
              Text(unit,
                  style: TextStyle(
                      fontSize: large ? 22 : 16, color: Colors.white60)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: large ? 70 : 40,
            width: double.infinity,
            child: CustomPaint(painter: SparklinePainter(values, color)),
          ),
          const SizedBox(height: 8),
          Text(footnote,
              style: const TextStyle(fontSize: 12, color: Colors.white38)),
        ],
      ),
    );
  }
}

class SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  SparklinePainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final range = (maxV - minV) < 0.001 ? 1.0 : maxV - minV;

    final line = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height - (values[i] - minV) / range * size.height;
      i == 0 ? line.moveTo(x, y) : line.lineTo(x, y);
    }

    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(SparklinePainter old) =>
      old.values != values || old.color != color;
}

class _Banner extends StatelessWidget {
  final String text;
  const _Banner(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: Colors.redAccent, size: 18),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}

class _SetupView extends StatelessWidget {
  final VoidCallback onEnterIp;
  const _SetupView({required this.onEnterIp});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          const Icon(Icons.router_outlined, size: 64, color: Colors.white54),
          const SizedBox(height: 16),
          const Text('Connect to your Raspberry Pi',
              style: TextStyle(fontSize: 18, color: Colors.white)),
          const SizedBox(height: 8),
          const Text(
            'Enter the Pi\'s IP address. The app will read\nhttp://<IP>:$serverPort$dataPath',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onEnterIp,
            icon: const Icon(Icons.edit),
            label: const Text('Enter IP address'),
          ),
        ],
      ),
    );
  }
}

class _OfflineView extends StatelessWidget {
  final String url;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onChangeIp;

  const _OfflineView({
    required this.url,
    required this.error,
    required this.onRetry,
    required this.onChangeIp,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          const Icon(Icons.wifi_off, size: 64, color: Colors.white54),
          const SizedBox(height: 16),
          const Text('Cannot reach the monitor',
              style: TextStyle(fontSize: 18, color: Colors.white)),
          const SizedBox(height: 8),
          Text(
            'Check that the Flask server is running, your phone is on the '
            'same Wi-Fi, and the IP is correct.\n\n$url',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.white38)),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: onChangeIp,
                icon: const Icon(Icons.edit),
                label: const Text('Change IP'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
