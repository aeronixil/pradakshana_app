import 'dart:async';
import 'package:flutter/material.dart';
import 'session_controller.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Pradakshina',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xffb85d28)),
          scaffoldBackgroundColor: const Color(0xfffffaf3),
          inputDecorationTheme:
              const InputDecorationTheme(border: OutlineInputBorder()),
        ),
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
  final prayer = TextEditingController();
  final scroll = ScrollController();
  double minimum = 80;

  @override
  void initState() {
    super.initState();
    counter = widget.controller ?? SessionController();
    WidgetsBinding.instance.addObserver(this);
    counter.addListener(_refresh);
    unawaited(counter.load());
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _begin() async {
    FocusScope.of(context).unfocus();
    await counter.begin(name.text, prayer.text, minimum);
    if (mounted && scroll.hasClients) scroll.jumpTo(0);
  }

  Future<void> _finish() async {
    await counter.finish();
    if (mounted && scroll.hasClients) scroll.jumpTo(0);
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

  @override
  Widget build(BuildContext context) {
    final active = counter.active;
    return Scaffold(
      appBar: AppBar(
          title: const Text('Pradakshina'),
          backgroundColor: const Color(0xfffffaf3)),
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Text('Every circle, a moment of devotion.',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text('Walk mindfully. Let GPS keep count.'),
              const SizedBox(height: 20),
              if (counter.storageError != null)
                panel(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(counter.storageError!,
                          style: const TextStyle(color: Colors.red)),
                      if (counter.ready)
                        TextButton(
                            onPressed: counter.save,
                            child: const Text('Retry save')),
                    ])),
              if (!counter.ready && counter.storageError == null)
                const LinearProgressIndicator(),
              if (active == null)
                panel(Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Begin your practice',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 16),
                      TextField(
                          controller: name,
                          maxLength: 100,
                          decoration: const InputDecoration(
                              labelText: 'Temple or place (optional)')),
                      const SizedBox(height: 12),
                      TextField(
                          controller: prayer,
                          minLines: 3,
                          maxLines: 6,
                          maxLength: 10000,
                          decoration: const InputDecoration(
                              labelText: 'Prayer or mantra (optional)',
                              hintText: 'Write or paste in Hindi or English')),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<double>(
                        value: minimum,
                        decoration: const InputDecoration(
                            labelText: 'Minimum distance for one loop'),
                        items: [60.0, 80.0, 150.0, 300.0, 500.0, 1000.0]
                            .map((m) => DropdownMenuItem(
                                value: m, child: Text('${m.toInt()} metres')))
                            .toList(),
                        onChanged: (v) => setState(() => minimum = v!),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                          onPressed: counter.ready ? _begin : null,
                          icon: const Icon(Icons.self_improvement),
                          label: const Text('Begin session')),
                    ]))
              else
                panel(Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(active['name'] as String,
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Center(
                          child: Text('${counter.currentCount}',
                              style: const TextStyle(
                                  fontSize: 88,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xff9b491e)))),
                      const Center(child: Text('pradakshinas this session')),
                      const SizedBox(height: 20),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                                counter.tracking
                                    ? Icons.gps_fixed
                                    : Icons.gps_off,
                                color: const Color(0xff9b491e)),
                            const SizedBox(width: 10),
                            Expanded(child: Text(counter.status)),
                          ]),
                      if (counter.tracking)
                        Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                                '${counter.tracker.distance.toStringAsFixed(0)} m this loop'
                                '${counter.accuracy == null ? '' : ' · GPS ±${counter.accuracy!.toStringAsFixed(0)} m'}')),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                          onPressed: counter.busy
                              ? null
                              : counter.tracking
                                  ? () => counter.pause()
                                  : counter.startGps,
                          icon: Icon(counter.tracking
                              ? Icons.pause
                              : Icons.my_location),
                          label: Text(counter.busy
                              ? 'Connecting…'
                              : counter.tracking
                                  ? 'Pause GPS'
                                  : 'Start GPS tracking')),
                      const SizedBox(height: 8),
                      Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
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
                            TextButton(
                                onPressed: _finish,
                                child: const Text('Finish session')),
                          ]),
                      if ((active['prayer'] as String).isNotEmpty) ...[
                        const Divider(height: 32),
                        SelectableText(active['prayer'] as String,
                            style: const TextStyle(fontSize: 22, height: 1.7)),
                      ],
                    ])),
              const SizedBox(height: 12),
              panel(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('How automatic counting works',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                        'Start GPS on your walking path and wait for a start point. Walk a complete loop around the temple and return within 10 m of where you started. Each loop must take at least 30 seconds and move at least 25 m away from the start.'),
                    const SizedBox(height: 8),
                    Text(counter.canBackground
                        ? 'Android shows a notification during tracking. Pause or finish to stop location use. Battery settings may interrupt GPS.'
                        : 'Keep this page visible and your screen awake. Tracking pauses when the app is hidden; resume begins a new loop.'),
                    const SizedBox(height: 8),
                    const Text(
                        'Best outdoors on larger paths. Small indoor circuits and weak GPS need manual counting. Counts and timestamps stay on this device; your route is not stored or uploaded. Clearing app/browser data removes history.'),
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
                    ],
                  ))),
            ]),
      ))),
    );
  }
}
