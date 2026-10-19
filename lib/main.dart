import 'dart:async';
import 'package:flutter/material.dart';
import 'hanuman_chalisa.dart';
import 'prayer_reader.dart';
import 'session_controller.dart';
import 'insights.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Pradakshina',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            useMaterial3: true,
            colorScheme:
                ColorScheme.fromSeed(seedColor: const Color(0xffb85d28)),
            scaffoldBackgroundColor: const Color(0xfffffaf3),
            inputDecorationTheme:
                const InputDecorationTheme(border: OutlineInputBorder())),
        home: const HomeScreen(),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.controller});
  final SessionController? controller;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final SessionController counter;
  final name = TextEditingController();
  final prayer = TextEditingController(text: hanumanChalisa);
  final scroll = ScrollController();
  double minimum = 80;

  @override
  void initState() {
    super.initState();
    counter = widget.controller ?? SessionController();
    WidgetsBinding.instance.addObserver(this);
    counter.addListener(_refresh);
    unawaited(_load());
  }

  Future<void> _load() async {
    await counter.load();
    // Supply the reading for an older, unfinished session with an empty prayer.
    // Existing custom prayers are preserved.
    if (mounted &&
        counter.active != null &&
        (counter.active!['prayer'] as String).trim().isEmpty) {
      await counter.updatePrayer(hanumanChalisa);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _begin({bool gps = true}) async {
    FocusScope.of(context).unfocus();
    await counter.begin(name.text,
        prayer.text.trim().isEmpty ? hanumanChalisa : prayer.text, minimum);
    if (mounted && gps) await counter.startGps();
  }

  Future<void> _finish() async {
    // Keep any custom reading available for the next session, too.
    prayer.text = counter.active?['prayer'] as String? ?? hanumanChalisa;
    final session = counter.active;
    await counter.finish();
    if (mounted) _insights(session);
  }

  void _insights([Map<String, dynamic>? session]) {
    Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => Insights(controller: counter, session: session)));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!counter.canBackground &&
        (state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused) &&
        (counter.tracking || counter.busy)) {
      unawaited(counter.pause(
          message:
              'Tracking paused while the app was hidden. Resume for a new loop.'));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    counter.removeListener(_refresh);
    counter.dispose();
    name.dispose();
    prayer.dispose();
    scroll.dispose();
    super.dispose();
  }

  String date(String value) {
    final d = DateTime.parse(value).toLocal();
    return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget panel(Widget child) => Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(padding: const EdgeInsets.all(20), child: child));

  Widget _storageNotice() => Padding(
      padding: const EdgeInsets.all(8),
      child: Row(children: [
        Expanded(
            child: Text(counter.storageError!,
                style: const TextStyle(color: Colors.red))),
        if (counter.ready)
          TextButton(onPressed: counter.save, child: const Text('Retry save')),
      ]));

  void _sessionControls() {
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
                child: AnimatedBuilder(
              animation: counter,
              builder: (context, _) => SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Session controls',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        Text(counter.active?['name'] as String? ?? ''),
                        const SizedBox(height: 12),
                        Text(counter.status),
                        if (counter.tracking)
                          Text(
                              '${counter.tracker.distance.toStringAsFixed(0)} m this loop'
                              '${counter.accuracy == null ? '' : ' · GPS ±${counter.accuracy!.toStringAsFixed(0)} m'}'),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                            onPressed: () => counter.adjust(1),
                            icon: const Icon(Icons.add),
                            label: const Text('Add manually')),
                        OutlinedButton.icon(
                            onPressed: counter.currentCount > 0
                                ? () => counter.adjust(-1)
                                : null,
                            icon: const Icon(Icons.remove),
                            label: const Text('Correct −1')),
                        const SizedBox(height: 8),
                        FilledButton(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              unawaited(_finish());
                            },
                            child: const Text('Finish session')),
                        TextButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('Back to reading')),
                      ])),
            )));
  }

  Widget _readingScreen() => Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                        child: Text('Read & walk',
                            style: Theme.of(context).textTheme.titleMedium)),
                    FilledButton.icon(
                        onPressed: counter.busy
                            ? null
                            : counter.tracking
                                ? () => counter.pause()
                                : counter.startGps,
                        icon: Icon(
                            counter.tracking ? Icons.pause : Icons.my_location,
                            size: 18),
                        label: Text(counter.busy
                            ? 'Connecting…'
                            : counter.tracking
                                ? 'Pause'
                                : 'Start GPS')),
                  ]),
                  Row(children: [
                    Expanded(
                        child: _counterControls(
                      '${counter.currentCount} pradakshinas',
                      'pradakshina',
                      counter.currentCount,
                      (delta) => counter.adjust(delta),
                      key: const Key('live-count'),
                    )),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _counterControls(
                      '${counter.currentReadings} readings',
                      'reading',
                      counter.currentReadings,
                      (delta) => counter.adjustReading(delta),
                      key: const Key('reading-count'),
                    )),
                  ]),
                  const SizedBox(height: 4),
                  Text(counter.status,
                      key: const Key('gps-status'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                ])),
        if (counter.storageError != null) _storageNotice(),
        Expanded(
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: PrayerReader(
                  key: ValueKey(counter.active!['startedAt']),
                  text: counter.active!['prayer'] as String,
                  onChanged: (text) => unawaited(counter.updatePrayer(text)),
                  onRead: (language) => unawaited(counter.adjustReading(1,
                      source: 'scroll', language: language)),
                ))),
      ]);

  Widget _counterControls(
          String label, String kind, int value, ValueChanged<int> adjust,
          {Key? key}) =>
      DecoratedBox(
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          IconButton(
              tooltip: 'Subtract $kind',
              onPressed: value > 0 ? () => adjust(-1) : null,
              icon: const Icon(Icons.remove),
              visualDensity: VisualDensity.compact),
          Expanded(
              child: Text(label,
                  key: key,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600))),
          IconButton(
              tooltip: 'Add $kind',
              onPressed: () => adjust(1),
              icon: const Icon(Icons.add),
              visualDensity: VisualDensity.compact),
        ]),
      );

  Widget _setupScreen() => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text('Read. Walk. Let GPS count.',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
                'Hanuman Chalisa is ready below. You can edit it or paste another prayer.'),
            const SizedBox(height: 12),
            if (counter.storageError != null) _storageNotice(),
            if (!counter.ready && counter.storageError == null)
              const LinearProgressIndicator(),
            FilledButton.icon(
                onPressed: counter.ready ? () => _begin() : null,
                icon: const Icon(Icons.menu_book),
                label: const Text('Read & start GPS')),
            TextButton(
                onPressed: counter.ready ? () => _begin(gps: false) : null,
                child: const Text('Read without GPS')),
            const SizedBox(height: 8),
            TextField(
                key: const Key('prayer-input'),
                controller: prayer,
                minLines: 7,
                maxLines: 10,
                maxLength: 10000,
                style: const TextStyle(
                    fontFamily: 'NotoDevanagari', fontSize: 22, height: 1.6),
                decoration: const InputDecoration(
                    labelText: 'Hanuman Chalisa / your prayer',
                    filled: true,
                    fillColor: Colors.white,
                    alignLabelWithHint: true,
                    hintText: 'Write or paste in Hindi or English')),
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                    onPressed: () => prayer.text = hanumanChalisa,
                    child: const Text('Load Hanuman Chalisa'))),
            Card(
                elevation: 0,
                color: Colors.white,
                child: ExpansionTile(
                    title: const Text('Place & loop settings'),
                    childrenPadding: const EdgeInsets.all(16),
                    children: [
                      TextField(
                          key: const Key('place-input'),
                          controller: name,
                          maxLength: 100,
                          decoration: const InputDecoration(
                              labelText: 'Temple or place (optional)')),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<double>(
                          value: minimum,
                          decoration: const InputDecoration(
                              labelText: 'Minimum distance for one loop'),
                          items: [60.0, 80.0, 150.0, 300.0, 500.0, 1000.0]
                              .map((m) => DropdownMenuItem(
                                  value: m, child: Text('${m.toInt()} metres')))
                              .toList(),
                          onChanged: (v) => setState(() => minimum = v!)),
                    ])),
            const SizedBox(height: 12),
            panel(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Automatic counting',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                  'Allow precise location and wait for a start point. Walk a full loop, at least 25 m away, and return within 10 m of your start. Each loop must take at least 30 seconds.'),
              const SizedBox(height: 8),
              Text(counter.canBackground
                  ? 'Android shows a notification while GPS counts. Battery restrictions can interrupt it.'
                  : 'Keep this page visible while reading. GPS pauses when the app is hidden. Screen-awake support depends on your browser.'),
              const SizedBox(height: 8),
              const Text(
                  'Best outdoors on larger paths. Small indoor circuits need manual counting. Counts and timestamped paths stay on this device; clearing app/browser data removes them. Open Insights for graphs and maps.'),
            ])),
            const SizedBox(height: 20),
            Text('Your practice · ${counter.total} total',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (counter.sessions.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Your saved sessions will appear here.')),
            ...counter.sessions.map((s) => Card(
                elevation: 0,
                color: Colors.white,
                child: ExpansionTile(
                    title: Text('${s['name']} · ${counter.count(s)}'),
                    subtitle: Text(
                        '${date(s['startedAt'] as String)} · ${s['endedAt'] == null ? 'In progress' : 'Finished'}'),
                    children: [
                      TextButton.icon(
                          onPressed: () => _insights(s),
                          icon: const Icon(Icons.insights),
                          label: const Text('View insights & path')),
                      if ((s['events'] as List).isEmpty)
                        const ListTile(
                            title: Text('No completed pradakshinas yet.')),
                      ...(s['events'] as List).reversed.map((e) => ListTile(
                            leading: Icon(e['source'] == 'gps'
                                ? Icons.gps_fixed
                                : Icons.touch_app),
                            title: Text(e['delta'] == -1
                                ? 'Manual correction −1'
                                : e['source'] == 'gps'
                                    ? 'GPS pradakshina +1'
                                    : 'Manual pradakshina +1'),
                            subtitle: Text(
                                '${date(e['at'] as String)}${e['distance'] == null ? '' : ' · ${(e['distance'] as num).toStringAsFixed(0)} m · ${e['seconds']} sec'}'),
                          )),
                    ]))),
          ]);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Pradakshina'),
            backgroundColor: const Color(0xfffffaf3),
            actions: [
              IconButton(
                  onPressed: () => _insights(),
                  tooltip: 'Insights',
                  icon: const Icon(Icons.insights)),
              if (counter.active != null)
                IconButton(
                    onPressed: _sessionControls,
                    tooltip: 'Session controls',
                    icon: const Icon(Icons.tune))
            ]),
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: counter.active == null ? _setupScreen() : _readingScreen(),
        ))),
      );
}
