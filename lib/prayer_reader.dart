import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'hanuman_chalisa.dart';
import 'hanuman_chalisa_roman.dart';
import 'reading_tracker.dart';

/// Keeps its text controller and scroll position when GPS updates rebuild home.
class PrayerReader extends StatefulWidget {
  const PrayerReader({
    super.key,
    required this.text,
    required this.onChanged,
    this.onRead,
    this.initialRoman = true,
    this.initialFontSize = 24,
    this.onPreferencesChanged,
  });
  final String text;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onRead;
  final bool initialRoman;
  final double initialFontSize;
  final void Function(bool roman, double fontSize)? onPreferencesChanged;
  @override
  State<PrayerReader> createState() => _PrayerReaderState();
}

enum _ReadingOption { larger, smaller, edit, restore }

class _PrayerReaderState extends State<PrayerReader>
    with WidgetsBindingObserver {
  late final TextEditingController text = TextEditingController(
      text: _usingRoman ? hanumanChalisaRoman : widget.text);
  final scroll = ScrollController();
  final focus = FocusNode();
  late double fontSize = widget.initialFontSize.isFinite
      ? widget.initialFontSize.clamp(18.0, 36.0)
      : 24;
  bool editing = false;
  bool awakeFailed = false;
  late bool roman = widget.initialRoman;
  bool userScrolling = false, completed = false;
  final reading = ReadingTracker();
  bool get _builtIn => widget.text == hanumanChalisa;
  bool get _usingRoman => roman && _builtIn && !editing;

  void _savePreferences() => widget.onPreferencesChanged?.call(roman, fontSize);

  void _setRoman(bool value) {
    focus.unfocus();
    setState(() {
      roman = value;
      _resetReading();
      text.text = _usingRoman ? hanumanChalisaRoman : widget.text;
    });
    if (scroll.hasClients) scroll.jumpTo(0);
    _savePreferences();
  }

  void _setEditing(bool value) {
    focus.unfocus();
    setState(() {
      editing = value;
      _resetReading();
      // Edit the saved source, never silently replace it with the display script.
      text.text = _usingRoman ? hanumanChalisaRoman : widget.text;
    });
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  void _selectOption(_ReadingOption option) {
    switch (option) {
      case _ReadingOption.larger:
      case _ReadingOption.smaller:
        setState(() {
          fontSize = (fontSize + (option == _ReadingOption.larger ? 2 : -2))
              .clamp(18.0, 36.0);
          _resetReading();
        });
        _savePreferences();
      case _ReadingOption.edit:
        _setEditing(true);
      case _ReadingOption.restore:
        _resetReading();
        widget.onChanged(hanumanChalisa);
        focus.unfocus();
        if (scroll.hasClients) scroll.jumpTo(0);
    }
  }

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
        widget.onRead?.call(_usingRoman
            ? 'English letters'
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
    if (widget.text != oldWidget.text) {
      final displayed = _usingRoman ? hanumanChalisaRoman : widget.text;
      if (text.text != displayed) text.text = displayed;
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
          if (_builtIn && !editing)
            Expanded(
                child: DropdownButtonHideUnderline(
                    child: DropdownButton<bool>(
              key: const Key('reading-script'),
              value: roman,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: false, child: Text('हिंदी')),
                DropdownMenuItem(value: true, child: Text('English letters')),
              ],
              onChanged: (value) {
                if (value != null && value != roman) _setRoman(value);
              },
            )))
          else
            Expanded(child: Text(_builtIn ? 'हिंदी · Edit' : 'Your text')),
          if (editing)
            TextButton.icon(
                onPressed: () => _setEditing(false),
                icon: const Icon(Icons.check),
                label: const Text('Done')),
          PopupMenuButton<_ReadingOption>(
            tooltip: 'Reading options',
            icon: const Icon(Icons.text_fields),
            onSelected: _selectOption,
            itemBuilder: (context) => [
              PopupMenuItem(
                  value: _ReadingOption.larger,
                  enabled: fontSize < 36,
                  child: const Text('Larger text')),
              PopupMenuItem(
                  value: _ReadingOption.smaller,
                  enabled: fontSize > 18,
                  child: const Text('Smaller text')),
              if (!editing)
                PopupMenuItem(
                    value: _ReadingOption.edit,
                    child: Text(_usingRoman
                        ? 'Edit original Hindi text'
                        : 'Edit text')),
              if (!_builtIn)
                const PopupMenuItem(
                    value: _ReadingOption.restore,
                    child: Text('Load Hanuman Chalisa')),
            ],
          ),
        ]),
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
