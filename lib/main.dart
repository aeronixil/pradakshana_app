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
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff9a542b)),
          scaffoldBackgroundColor: const Color(0xfffffaf3),
          inputDecorationTheme:
              const InputDecorationTheme(border: OutlineInputBorder())),
      home: const HomeScreen());
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.controller});
  final SessionController? controller;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final SessionController counter;
  String prayer = hanumanChalisa, placeName = 'My place';
  Map<String, dynamic>? selectedPlace;
  double minimum = 80;
  bool loaded = false, starting = false;
  @override
  void initState() {
    super.initState();
    counter = widget.controller ?? SessionController();
    counter.addListener(_refresh);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() async {
    await counter.load();
    if (!mounted) return;
    final previous = counter.active ?? counter.sessions.firstOrNull;
    if (previous != null) {
      final savedPrayer = previous['prayer'] as String;
      prayer = savedPrayer.trim().isEmpty ? hanumanChalisa : savedPrayer;
      minimum = (previous['minimumDistance'] as num).toDouble();
      placeName = previous['name'] as String;
    }
    selectedPlace = counter.latestPlace;
    if (counter.active == null && selectedPlace != null) {
      _selectPlace(selectedPlace!);
    }
    if (counter.active != null &&
        (counter.active!['prayer'] as String).trim().isEmpty) {
      await counter.updatePrayer(hanumanChalisa);
    }
    if (mounted) setState(() => loaded = true);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _selectPlace(Map<String, dynamic> place) {
    selectedPlace = place;
    placeName = place['name'] as String;
    minimum = (place['minimumDistance'] as num? ?? 80).toDouble();
    final oldPrayer = place['prayer'] as String?;
    if (oldPrayer != null && oldPrayer.trim().isNotEmpty) prayer = oldPrayer;
  }

  Future<void> _begin({bool gps = true, bool unfocus = true}) async {
    if (starting || !counter.ready) return;
    setState(() => starting = true);
    if (unfocus) FocusScope.of(context).unfocus();
    try {
      if (counter.active == null) {
        await counter.begin(placeName, prayer, minimum, place: selectedPlace);
      }
      if (mounted && gps) await counter.startGps();
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  Future<void> _read(String language) async {
    if (counter.active == null) await _begin(gps: false);
    await counter.adjustReading(1, source: 'scroll', language: language);
  }

  Future<void> _finish() async {
    prayer = counter.active?['prayer'] as String? ?? prayer;
    final session = counter.active;
    await counter.finish();
    selectedPlace = counter.latestPlace;
    if (selectedPlace != null) _selectPlace(selectedPlace!);
    if (mounted) _insights(session);
  }

  void _insights([Map<String, dynamic>? session]) => Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => Insights(
              controller: counter,
              session: session,
              onUsePlace: counter.active != null
                  ? null
                  : (place) {
                      Navigator.pop(context);
                      setState(() => _selectPlace(place));
                    })));
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!counter.canBackground &&
        (state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused) &&
        (counter.tracking || counter.busy)) {
      unawaited(counter.pause(
          message: 'GPS paused. Keep this page open while walking.'));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    counter.removeListener(_refresh);
    counter.dispose();
    super.dispose();
  }

  Future<void> _places() async {
    final name = TextEditingController(
        text: counter.active?['name'] as String? ?? placeName);
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheet) => SafeArea(
            child: AnimatedBuilder(
                animation: counter,
                builder: (context, _) => SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(24, 24, 24,
                        24 + MediaQuery.viewInsetsOf(context).bottom),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Your places',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          Text(counter.active == null
                              ? 'Your last place is ready. Choose another from history, or mark a new start.'
                              : 'Stand where each round begins. A fresh GPS reading is needed to mark it.'),
                          if (counter.active == null)
                            ...counter.places.map((place) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.location_on_outlined),
                                title: Text(place['name'] as String),
                                subtitle: Text(
                                    'Saved ${stamp(place['markedAt']).split(' ').first} · from your history'),
                                trailing: selectedPlace?['id'] == place['id']
                                    ? const Icon(Icons.check)
                                    : null,
                                onTap: () {
                                  setState(() => _selectPlace(place));
                                  Navigator.pop(sheet);
                                })),
                          const SizedBox(height: 12),
                          TextField(
                              controller: name,
                              key: const Key('place-input'),
                              maxLength: 100,
                              decoration: const InputDecoration(
                                  labelText: 'Place name')),
                          if (counter.active == null) ...[
                            ExpansionTile(
                                title: const Text('Loop settings'),
                                children: [
                                  DropdownButtonFormField<double>(
                                      value: minimum,
                                      decoration: const InputDecoration(
                                          labelText:
                                              'Minimum distance for one round'),
                                      items: {
                                        60.0,
                                        80.0,
                                        150.0,
                                        300.0,
                                        500.0,
                                        1000.0,
                                        minimum
                                      }
                                          .map((m) => DropdownMenuItem(
                                              value: m,
                                              child:
                                                  Text('${m.round()} metres')))
                                          .toList(),
                                      onChanged: (v) => minimum = v!),
                                  const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 12),
                                      child: Text(
                                          'GPS works best outdoors. Walk at least 25 m away and return to the start. Use manual counts for small indoor rounds.')),
                                ]),
                            FilledButton.icon(
                                icon:
                                    const Icon(Icons.add_location_alt_outlined),
                                label: const Text('Use a new place'),
                                onPressed: () {
                                  setState(() {
                                    selectedPlace = null;
                                    placeName = name.text.trim().isEmpty
                                        ? 'My place'
                                        : name.text.trim();
                                  });
                                  Navigator.pop(sheet);
                                }),
                            const Text(
                                'When you begin, the first accurate GPS fix saves your start automatically.',
                                style: TextStyle(fontSize: 12)),
                          ] else ...[
                            if (!counter.tracking)
                              FilledButton(
                                  onPressed:
                                      counter.busy ? null : counter.startGps,
                                  child: const Text('Start GPS to mark')),
                            Text(counter.status,
                                style: const TextStyle(fontSize: 12)),
                            FilledButton.icon(
                                icon:
                                    const Icon(Icons.add_location_alt_outlined),
                                label: const Text('Mark this start point'),
                                onPressed: !counter.canMarkCurrentPlace
                                    ? null
                                    : () async {
                                        final marked =
                                            await counter.markCurrentPlace();
                                        if (marked) {
                                          await counter
                                              .renameCurrentPlace(name.text);
                                        }
                                        if (sheet.mounted && marked) {
                                          Navigator.pop(sheet);
                                        }
                                      }),
                            TextButton(
                                onPressed: () async {
                                  await counter.renameCurrentPlace(name.text);
                                  if (sheet.mounted) Navigator.pop(sheet);
                                },
                                child: const Text('Save name')),
                          ],
                          TextButton(
                              onPressed: () => Navigator.pop(sheet),
                              child: const Text('Back to prayer')),
                        ])))));
    await Future<void>.delayed(const Duration(milliseconds: 350));
    name.dispose();
  }

  Widget _adjust(
          String label, String kind, int count, ValueChanged<int> change) =>
      Row(children: [
        Expanded(child: Text('$label · $count')),
        IconButton(
            tooltip: 'Subtract $kind',
            onPressed: count > 0 ? () => change(-1) : null,
            icon: const Icon(Icons.remove)),
        IconButton(
            tooltip: 'Add $kind',
            onPressed: () => change(1),
            icon: const Icon(Icons.add)),
      ]);
  void _controls() => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
          child: AnimatedBuilder(
              animation: counter,
              builder: (context, _) => SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Your practice',
                            style: Theme.of(context).textTheme.titleLarge),
                        if (counter.active != null) ...[
                          _adjust('Pradakshinas', 'pradakshina',
                              counter.currentCount, (d) => counter.adjust(d)),
                          _adjust(
                              'Readings',
                              'reading',
                              counter.currentReadings,
                              (d) => counter.adjustReading(d)),
                          FilledButton.icon(
                              onPressed: counter.busy
                                  ? null
                                  : counter.tracking
                                      ? () => counter.pause()
                                      : counter.startGps,
                              icon: Icon(counter.tracking
                                  ? Icons.pause
                                  : Icons.my_location),
                              label: Text(counter.tracking
                                  ? 'Pause GPS'
                                  : 'Resume GPS')),
                          TextButton(
                              onPressed: () {
                                Navigator.pop(sheet);
                                unawaited(_finish());
                              },
                              child: const Text('Finish session')),
                        ],
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading:
                                const Icon(Icons.add_location_alt_outlined),
                            title: const Text('Saved places & GPS mark'),
                            onTap: () {
                              Navigator.pop(sheet);
                              unawaited(_places());
                            }),
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.history),
                            title: const Text('History & insights'),
                            onTap: () {
                              Navigator.pop(sheet);
                              _insights();
                            }),
                        const Text(
                            'Counts and saved places stay on this device. Keep this page visible for GPS.',
                            style: TextStyle(fontSize: 12)),
                        TextButton(
                            onPressed: () => Navigator.pop(sheet),
                            child: const Text('Back to prayer')),
                      ])))));
  @override
  Widget build(BuildContext context) {
    final active = counter.active;
    final place = active != null ? active['place'] as Map? : selectedPlace;
    return Scaffold(
        appBar: AppBar(
            title: const Text('Pradakshina'),
            backgroundColor: const Color(0xfffffaf3),
            actions: [
              IconButton(
                  tooltip: 'Session controls',
                  onPressed: _controls,
                  icon: const Icon(Icons.more_horiz))
            ]),
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: !loaded
                        ? const Center(child: CircularProgressIndicator())
                        : Column(children: [
                            if (counter.storageError != null)
                              Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(children: [
                                    Expanded(
                                        child: Text(counter.storageError!)),
                                    if (counter.ready)
                                      TextButton(
                                          onPressed: counter.save,
                                          child: const Text('Retry save'))
                                  ])),
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Column(children: [
                                  Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                          onPressed: _places,
                                          icon: Icon(
                                              place == null
                                                  ? Icons
                                                      .add_location_alt_outlined
                                                  : Icons.location_on_outlined,
                                              size: 18),
                                          label: Text(
                                              place == null
                                                  ? '$placeName · mark with GPS'
                                                  : '${place['name']} · saved start',
                                              overflow:
                                                  TextOverflow.ellipsis))),
                                  if (active == null)
                                    Row(children: [
                                      Expanded(
                                          child: FilledButton.icon(
                                              onPressed:
                                                  starting || !counter.ready
                                                      ? null
                                                      : () => _begin(),
                                              icon:
                                                  const Icon(Icons.play_arrow),
                                              label: const Text(
                                                  'Begin pradakshina'))),
                                      TextButton(
                                          onPressed: starting || !counter.ready
                                              ? null
                                              : () => _begin(gps: false),
                                          child: const Text('Just read')),
                                    ])
                                  else ...[
                                    Row(children: [
                                      Expanded(
                                          child: InkWell(
                                              onTap: _controls,
                                              child: Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 10),
                                                  child: Wrap(
                                                      spacing: 20,
                                                      children: [
                                                        Text(
                                                            '${counter.currentCount} pradakshinas',
                                                            key: const Key(
                                                                'live-count')),
                                                        Text(
                                                            '${counter.currentReadings} readings',
                                                            key: const Key(
                                                                'reading-count'))
                                                      ])))),
                                      IconButton(
                                          tooltip: counter.tracking
                                              ? 'Pause GPS'
                                              : 'Resume GPS',
                                          onPressed: counter.busy
                                              ? null
                                              : counter.tracking
                                                  ? () => counter.pause()
                                                  : counter.startGps,
                                          icon: Icon(counter.tracking
                                              ? Icons.pause_circle_outline
                                              : Icons.my_location)),
                                    ]),
                                    Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(counter.status,
                                            key: const Key('gps-status'),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style:
                                                const TextStyle(fontSize: 12))),
                                  ],
                                ])),
                            Expanded(
                                child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16),
                                    child: PrayerReader(
                                      key: const Key('devotion-reader'),
                                      text: active?['prayer'] as String? ??
                                          prayer,
                                      initialRoman: counter.preferredRoman,
                                      initialFontSize:
                                          counter.preferredFontSize,
                                      onPreferencesChanged: (roman, size) =>
                                          unawaited(
                                              counter.updateReadingPreferences(
                                                  roman: roman,
                                                  fontSize: size)),
                                      onChanged: (text) {
                                        setState(() => prayer = text);
                                        unawaited(() async {
                                          if (counter.active == null) {
                                            await _begin(
                                                gps: false, unfocus: false);
                                          }
                                          if (prayer == text) {
                                            await counter.updatePrayer(text);
                                          }
                                        }());
                                      },
                                      onRead: counter.ready
                                          ? (language) =>
                                              unawaited(_read(language))
                                          : null,
                                    ))),
                          ])))));
  }
}
