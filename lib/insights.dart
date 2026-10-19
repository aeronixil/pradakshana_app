import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'session_controller.dart';

String stamp(String value) {
  final d = DateTime.parse(value).toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${d.day}/${d.month}/${d.year} ${pad(d.hour)}:${pad(d.minute)}:${pad(d.second)}';
}

double routeDistance(List route) {
  var metres = 0.0;
  const distance = Distance(roundResult: false);
  for (var i = 1; i < route.length; i++) {
    if (route[i]['segment'] == route[i - 1]['segment']) {
      metres += distance.as(
          LengthUnit.Meter, coordinate(route[i - 1]), coordinate(route[i]));
    }
  }
  return metres;
}

LatLng coordinate(dynamic point) =>
    LatLng((point['lat'] as num).toDouble(), (point['lng'] as num).toDouble());

class Insights extends StatefulWidget {
  const Insights({super.key, required this.controller, this.session});
  final SessionController controller;
  final Map<String, dynamic>? session;
  @override
  State<Insights> createState() => _InsightsState();
}

class _InsightsState extends State<Insights> {
  late Map<String, dynamic>? selected = widget.session ??
      widget.controller.active ??
      widget.controller.sessions.firstOrNull;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
              title: const Text('Insights'),
              bottom: const TabBar(tabs: [
                Tab(text: 'Summary'),
                Tab(text: 'Paths'),
                Tab(text: 'Timeline'),
              ])),
          body: SafeArea(
              child: Center(
                  child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: AnimatedBuilder(
                animation: widget.controller,
                builder: (context, _) {
                  if (selected == null) {
                    return const Center(
                        child: Text('Your first session will appear here.'));
                  }
                  final session = selected!;
                  return Column(children: [
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: DropdownButtonFormField<String>(
                          value: session['startedAt'] as String,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'Session'),
                          items: widget.controller.sessions
                              .map((s) => DropdownMenuItem(
                                    value: s['startedAt'] as String,
                                    child: Text(
                                        '${s['name']} · ${stamp(s['startedAt']).substring(0, stamp(s['startedAt']).length - 3)}',
                                        overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (id) => setState(() => selected = widget
                              .controller.sessions
                              .firstWhere((s) => s['startedAt'] == id)),
                        )),
                    Expanded(
                        child: TabBarView(children: [
                      _summary(session),
                      SessionPaths(
                          key: ValueKey(session['startedAt']),
                          session: session,
                          controller: widget.controller),
                      _timeline(session),
                    ])),
                  ]);
                }),
          ))),
        ),
      );

  Widget _summary(Map<String, dynamic> s) {
    final c = widget.controller;
    final laps =
        (s['events'] as List).where((e) => e['source'] == 'gps').toList();
    final end =
        DateTime.parse(s['endedAt'] as String? ?? c.now().toIso8601String());
    final duration = end.difference(DateTime.parse(s['startedAt'])).inMinutes;
    final average = laps.isEmpty
        ? null
        : laps.fold<num>(0, (sum, e) => sum + (e['seconds'] as num)) /
            laps.length;
    final today = c.now().toLocal();
    final days = List.generate(
        7, (i) => DateTime(today.year, today.month, today.day - 6 + i));
    final walks = <int>[], reads = <int>[];
    for (final day in days) {
      int sum(String field) => c.sessions.fold(
          0,
          (sum, session) =>
              sum +
              (session[field] as List? ?? []).fold<int>(0, (sum, event) {
                final at = DateTime.parse(event['at']).toLocal();
                return sum +
                    (at.year == day.year &&
                            at.month == day.month &&
                            at.day == day.day
                        ? event['delta'] as int
                        : 0);
              }));
      walks.add(sum('events'));
      reads.add(sum('readingEvents'));
    }
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            _metric('${c.count(s)}', 'Pradakshinas'),
            _metric('${c.readings(s)}', 'Readings'),
            _metric('${math.max(0, duration)} min', 'Session elapsed'),
            _metric(
                '${routeDistance(s['route'] as List? ?? []).toStringAsFixed(0)} m',
                'Recorded path'),
            _metric(average == null ? '—' : '${average.round()} sec',
                'Average GPS loop'),
            _metric('${laps.length}', 'GPS detections'),
          ]),
          const SizedBox(height: 12),
          const Text(
              'Elapsed time includes pauses. Counts include manual corrections; path distance includes only recorded GPS segments.',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 24),
          Text('Last 7 days · all sessions',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('Orange: pradakshinas · Teal: readings',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          DailyBars(days: days, walks: walks, readings: reads),
          if (walks.any((v) => v < 0) || reads.any((v) => v < 0))
            const Text(
                'Negative daily adjustments are shown as labels; bars start at zero.',
                style: TextStyle(fontSize: 12)),
          const SizedBox(height: 16),
          Text(
              'All time: ${c.total} pradakshinas · ${c.totalReadings} readings · ${c.sessions.length} sessions'),
          if (laps.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('GPS loop durations',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...List.generate(laps.length, (i) {
              final maxSeconds =
                  laps.fold<num>(1, (v, e) => math.max(v, e['seconds'] as num));
              return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Loop ${i + 1} · ${laps[i]['seconds']} sec · ${(laps[i]['distance'] as num).round()} m'),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                            value: (laps[i]['seconds'] as num) / maxSeconds,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(6)),
                      ]));
            }),
          ],
          const SizedBox(height: 20),
          const Text(
              'Reading totals estimate completed scrolling, not attention or recitation. Use +/− to correct them.',
              style: TextStyle(fontSize: 12)),
        ]);
  }

  Widget _metric(String value, String label) => SizedBox(
      width: 158,
      child: Card(
          elevation: 0,
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 25, fontWeight: FontWeight.w600)),
              Text(label, style: const TextStyle(fontSize: 12)),
            ]),
          )));

  Widget _timeline(Map<String, dynamic> s) {
    final events = [
      ...(s['events'] as List).map((e) => {...e as Map, 'kind': 'Pradakshina'}),
      ...(s['readingEvents'] as List? ?? [])
          .map((e) => {...e as Map, 'kind': 'Reading'}),
    ]..sort(
        (a, b) => DateTime.parse(b['at']).compareTo(DateTime.parse(a['at'])));
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(s['endedAt'] == null
                  ? 'Session in progress'
                  : 'Session finished'),
              subtitle: Text(stamp(s['endedAt'] ?? s['startedAt']))),
          if (events.isEmpty)
            const ListTile(
                title: Text(
                    'No counts yet. Your GPS, scroll and manual entries will appear here.')),
          ...events.map((e) => ListTile(
                leading: Icon(e['kind'] == 'Reading'
                    ? Icons.menu_book
                    : e['source'] == 'gps'
                        ? Icons.gps_fixed
                        : Icons.touch_app),
                title: Text(
                    '${e['kind']} ${e['delta'] == 1 ? '+1' : '−1'} · ${e['source']}'),
                subtitle: Text(
                    '${stamp(e['at'])}${e['language'] == null ? '' : '\n${e['language']}'}${e['seconds'] == null ? '' : '\n${(e['distance'] as num).round()} m · ${e['seconds']} sec'}'),
                isThreeLine: e['language'] != null || e['seconds'] != null,
              )),
          ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: const Text('Session started'),
              subtitle: Text(stamp(s['startedAt']))),
        ]);
  }
}

class DailyBars extends StatelessWidget {
  const DailyBars(
      {super.key,
      required this.days,
      required this.walks,
      required this.readings});
  final List<DateTime> days;
  final List<int> walks, readings;
  @override
  Widget build(BuildContext context) {
    final maxValue = [...walks, ...readings].fold<int>(1, math.max);
    Widget bar(int value, Color color) => Expanded(
        child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 96 * math.max(0, value) / maxValue,
              width: 12,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(3)),
            )));
    return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(
            days.length,
            (i) => Expanded(
                    child: Semantics(
                  label:
                      '${days[i].day}/${days[i].month}: ${walks[i]} pradakshinas, ${readings[i]} readings',
                  child: Column(children: [
                    Text('${walks[i]} / ${readings[i]}',
                        style: const TextStyle(fontSize: 11)),
                    SizedBox(
                        height: 104,
                        child: Row(children: [
                          bar(walks[i], Colors.deepOrange.shade400),
                          bar(readings[i], Colors.teal)
                        ])),
                    const Divider(height: 1),
                    const SizedBox(height: 6),
                    Text('${days[i].day}/${days[i].month}',
                        style: const TextStyle(fontSize: 11)),
                  ]),
                ))));
  }
}

class SessionPaths extends StatefulWidget {
  const SessionPaths(
      {super.key,
      required this.session,
      required this.controller,
      this.allowTiles = true});
  final Map<String, dynamic> session;
  final SessionController controller;
  final bool allowTiles;
  @override
  State<SessionPaths> createState() => _SessionPathsState();
}

class _SessionPathsState extends State<SessionPaths> {
  bool showMap = false;
  int lap = -1;
  int? pointIndex;

  @override
  Widget build(BuildContext context) {
    final route = widget.session['route'] as List? ?? [];
    final laps = (widget.session['events'] as List)
        .where((e) => e['source'] == 'gps' && e['startedAt'] != null)
        .toList();
    final points = lap == -1
        ? route
        : route.where((p) {
            final time = DateTime.parse(p['at']);
            return !time.isBefore(DateTime.parse(laps[lap]['startedAt'])) &&
                !time.isAfter(DateTime.parse(laps[lap]['at']));
          }).toList();
    final index = points.isEmpty
        ? 0
        : (pointIndex ?? points.length - 1).clamp(0, points.length - 1);
    final segments = <List<LatLng>>[];
    for (var i = 0; i < points.length; i++) {
      if (i == 0 || points[i]['segment'] != points[i - 1]['segment']) {
        segments.add([]);
      }
      segments.last.add(coordinate(points[i]));
    }
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          if (widget.session['routeFull'] == true)
            const Card(
                child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                        'Path storage reached its limit. Counting continues. Remove an older session’s path to free space.'))),
          if (route.isEmpty)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                    'No recorded path for this session. New GPS sessions save accurate points here. Older sessions and manual counts have no path.')),
          if (route.isNotEmpty) ...[
            DropdownButtonFormField<int>(
              value: lap,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Path'),
              items: [
                const DropdownMenuItem(value: -1, child: Text('Whole session')),
                ...List.generate(
                    laps.length,
                    (i) => DropdownMenuItem(
                        value: i,
                        child: Text(
                            'GPS loop ${i + 1} · ${stamp(laps[i]['at']).split(' ').last}'))),
              ],
              onChanged: (value) => setState(() {
                lap = value!;
                pointIndex = null;
              }),
            ),
            const SizedBox(height: 12),
            if (points.isEmpty)
              const Text('No saved GPS points for this loop.'),
            if (points.isNotEmpty) ...[
              Text(
                  '${stamp(points.first['at'])}\n→ ${stamp(points.last['at'])}'),
              const SizedBox(height: 8),
              Text(
                  '${points.length} points · ${segments.length} segments · ${routeDistance(points).round()} m recorded'),
              const SizedBox(height: 12),
              if (!showMap) ...[
                const Text(
                    'Your path stays on this device. Opening the map requests the displayed area from OpenStreetMap.',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                FilledButton.icon(
                    onPressed: () => setState(() => showMap = true),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Show map')),
              ] else
                SizedBox(
                    height: 340,
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: FlutterMap(
                          key: ValueKey('${widget.session['startedAt']}-$lap'),
                          options: MapOptions(
                            initialCenter: coordinate(points.first),
                            initialZoom: 18,
                            maxZoom: 19,
                            initialCameraFit: points.length < 2
                                ? null
                                : CameraFit.bounds(
                                    bounds: LatLngBounds.fromPoints(
                                        points.map(coordinate).toList()),
                                    padding: const EdgeInsets.all(40),
                                    maxZoom: 18),
                            interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.all &
                                    ~InteractiveFlag.rotate),
                          ),
                          children: [
                            if (widget.allowTiles)
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'app.pradakshina.counter',
                                maxNativeZoom: 19,
                              ),
                            PolylineLayer(
                                polylines: segments
                                    .where((s) => s.length > 1)
                                    .map((s) => Polyline(
                                        points: s,
                                        strokeWidth: 5,
                                        color: lap == -1
                                            ? Colors.teal
                                            : Colors.deepOrange))
                                    .toList()),
                            MarkerLayer(markers: [
                              Marker(
                                  point: coordinate(points.first),
                                  width: 32,
                                  height: 32,
                                  child: Tooltip(
                                      message:
                                          'Start · ${stamp(points.first['at'])}',
                                      child: const Icon(Icons.trip_origin,
                                          color: Colors.green, size: 28))),
                              Marker(
                                  point: coordinate(points[index]),
                                  width: 40,
                                  height: 40,
                                  child: Tooltip(
                                      message: stamp(points[index]['at']),
                                      child: const Icon(Icons.location_on,
                                          color: Colors.deepOrange, size: 38))),
                            ]),
                            Align(
                                alignment: Alignment.bottomRight,
                                child: Material(
                                    color: Colors.white,
                                    child: InkWell(
                                      onTap: () => launchUrl(Uri.parse(
                                          'https://www.openstreetmap.org/copyright')),
                                      child: const Padding(
                                          padding: EdgeInsets.all(6),
                                          child: Text(
                                              '© OpenStreetMap contributors',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  decoration: TextDecoration
                                                      .underline))),
                                    ))),
                          ],
                        ))),
              const SizedBox(height: 12),
              Text('Selected point · ${stamp(points[index]['at'])}',
                  key: const Key('path-time')),
              if (points.length > 1)
                Slider(
                  key: const Key('path-slider'),
                  value: index.toDouble(),
                  min: 0,
                  max: (points.length - 1).toDouble(),
                  label: stamp(points[index]['at']),
                  onChanged: (value) =>
                      setState(() => pointIndex = value.round()),
                ),
              Text(
                  '${(points[index]['lat'] as num).toStringAsFixed(6)}, ${(points[index]['lng'] as num).toStringAsFixed(6)}',
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              const Text(
                  'Drag the slider to trace timestamped positions. Gaps and pauses stay disconnected; GPS paths are approximate.',
                  style: TextStyle(fontSize: 12)),
            ],
            const SizedBox(height: 16),
            TextButton(
                onPressed: () async {
                  final remove = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                            title: const Text('Remove this saved path?'),
                            content: const Text(
                                'Counts, readings and timestamps will remain. The coordinates cannot be recovered.'),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel')),
                              TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Remove path'))
                            ],
                          ));
                  if (remove == true) {
                    await widget.controller.clearRoute(widget.session);
                    if (mounted) {
                      setState(() {
                        pointIndex = null;
                      });
                    }
                  }
                },
                child: const Text('Remove saved path')),
          ],
        ]);
  }
}
