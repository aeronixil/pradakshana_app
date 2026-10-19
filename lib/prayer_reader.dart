import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'hanuman_chalisa.dart';

/// Keeps its text controller and scroll position when GPS updates rebuild home.
class PrayerReader extends StatefulWidget {
  const PrayerReader({super.key, required this.text, required this.onChanged});
  final String text;
  final ValueChanged<String> onChanged;
  @override
  State<PrayerReader> createState() => _PrayerReaderState();
}

class _PrayerReaderState extends State<PrayerReader>
    with WidgetsBindingObserver {
  late final TextEditingController text =
      TextEditingController(text: widget.text);
  final scroll = ScrollController();
  final focus = FocusNode();
  double fontSize = 24;
  bool editing = false;
  bool awakeFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_keepAwake());
  }

  Future<void> _keepAwake() async {
    try {
      await WakelockPlus.enable();
      if (mounted && awakeFailed) setState(() => awakeFailed = false);
    } catch (_) {
      if (mounted) setState(() => awakeFailed = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_keepAwake());
  }

  @override
  void didUpdateWidget(PrayerReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != text.text) text.text = widget.text;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(WakelockPlus.disable().catchError((Object _) {}));
    text.dispose();
    scroll.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Row(children: [
          const Expanded(
              child: Text('पाठ · Reading',
                  style: TextStyle(fontWeight: FontWeight.w600))),
          IconButton(
              tooltip: 'Smaller text',
              onPressed:
                  fontSize > 18 ? () => setState(() => fontSize -= 2) : null,
              icon: const Icon(Icons.text_decrease)),
          IconButton(
              tooltip: 'Larger text',
              onPressed:
                  fontSize < 36 ? () => setState(() => fontSize += 2) : null,
              icon: const Icon(Icons.text_increase)),
          TextButton.icon(
              onPressed: () {
                focus.unfocus();
                setState(() => editing = !editing);
              },
              icon: Icon(editing ? Icons.check : Icons.edit_outlined),
              label: Text(editing ? 'Done' : 'Edit')),
        ]),
        if (editing)
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                  onPressed: () {
                    text.text = hanumanChalisa;
                    widget.onChanged(text.text);
                    focus.unfocus();
                    if (scroll.hasClients) scroll.jumpTo(0);
                  },
                  child: const Text('Load Hanuman Chalisa'))),
        Expanded(
            child: Scrollbar(
          controller: scroll,
          thumbVisibility: true,
          child: TextField(
            key: const Key('prayer-reader'),
            controller: text,
            scrollController: scroll,
            focusNode: focus,
            readOnly: !editing,
            showCursor: editing,
            expands: true,
            minLines: null,
            maxLines: null,
            maxLength: 10000,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
            style: TextStyle(
                fontFamily: 'NotoDevanagari', fontSize: fontSize, height: 1.65),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              counterText: '',
              contentPadding: const EdgeInsets.all(20),
              hintText: 'Write or paste your prayer here',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onChanged: widget.onChanged,
          ),
        )),
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              awakeFailed
                  ? 'Keep your screen awake and this page open while reading.'
                  : 'Keep this page open. Your screen will stay awake where supported.',
              style: Theme.of(context).textTheme.bodySmall,
            )),
      ]);
}
