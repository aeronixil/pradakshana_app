import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'hanuman_chalisa.dart';
import 'hanuman_chalisa_english.dart';
import 'reading_tracker.dart';

/// Keeps its text controller and scroll position when GPS updates rebuild home.
class PrayerReader extends StatefulWidget {
  const PrayerReader(
      {super.key, required this.text, required this.onChanged, this.onRead});
  final String text;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onRead;
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
  bool english = false, userScrolling = false, completed = false;
  final reading = ReadingTracker();

  void _resetReading() {
    reading.reset();
    userScrolling = false;
    completed = false;
  }

  bool _onScroll(ScrollNotification event) {
    if (editing || event.metrics.maxScrollExtent <= 0) return false;
    final fraction =
        (event.metrics.pixels / event.metrics.maxScrollExtent).clamp(0.0, 1.0);
    if ((event is ScrollStartNotification && event.dragDetails != null) ||
        (event is UserScrollNotification &&
            event.direction != ScrollDirection.idle)) {
      userScrolling = true;
      reading.start(fraction);
    }
    if (event is ScrollUpdateNotification && userScrolling) {
      if (reading.update(fraction)) {
        widget.onRead?.call(english
            ? 'English meaning'
            : widget.text == hanumanChalisa
                ? 'Hindi'
                : 'Custom prayer');
        setState(() => completed = true);
      } else if (fraction <= .03 && completed) {
        setState(() => completed = false);
      }
    }
    if (event is ScrollEndNotification) userScrolling = false;
    return false;
  }

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
    if (!english && widget.text != text.text) {
      text.text = widget.text;
      _resetReading();
    }
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
          Expanded(
              child: DropdownButtonHideUnderline(
                  child: DropdownButton<bool>(
            value: english,
            isExpanded: true,
            items: [
              DropdownMenuItem(
                  value: false,
                  child: Text(
                      widget.text == hanumanChalisa ? 'हिंदी' : 'Your text')),
              const DropdownMenuItem(
                  value: true, child: Text('English meaning')),
            ],
            onChanged: (value) {
              focus.unfocus();
              setState(() {
                english = value!;
                editing = false;
                _resetReading();
                text.text = english ? hanumanChalisaEnglish : widget.text;
              });
              if (scroll.hasClients) scroll.jumpTo(0);
            },
          ))),
          IconButton(
              tooltip: 'Smaller text',
              onPressed: fontSize > 18
                  ? () => setState(() {
                        fontSize -= 2;
                        _resetReading();
                      })
                  : null,
              icon: const Icon(Icons.text_decrease)),
          IconButton(
              tooltip: 'Larger text',
              onPressed: fontSize < 36
                  ? () => setState(() {
                        fontSize += 2;
                        _resetReading();
                      })
                  : null,
              icon: const Icon(Icons.text_increase)),
          TextButton.icon(
              onPressed: english
                  ? null
                  : () {
                      focus.unfocus();
                      setState(() {
                        editing = !editing;
                        _resetReading();
                      });
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
            child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
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
                        fontFamily: 'NotoDevanagari',
                        fontSize: fontSize,
                        height: 1.65),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      counterText: '',
                      contentPadding: const EdgeInsets.all(20),
                      hintText: 'Write or paste your prayer here',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onChanged: (value) {
                      _resetReading();
                      widget.onChanged(value);
                    },
                  ),
                ))),
        if (completed)
          TextButton.icon(
            key: const Key('read-again'),
            onPressed: () {
              setState(_resetReading);
              if (scroll.hasClients) scroll.jumpTo(0);
            },
            icon: const Icon(Icons.replay),
            label: const Text('Reading counted · Read again'),
          ),
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              awakeFailed
                  ? 'Keep your screen awake and this page open while reading.'
                  : 'Scroll top → bottom to count a reading. Return to top to repeat.',
              style: Theme.of(context).textTheme.bodySmall,
            )),
      ]);
}
