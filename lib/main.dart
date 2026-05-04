import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

const double _kLabelFontSize = 24.0;
const double _kLabelPaddingFactor = 0.12;

Color _keyBackgroundColor(String label, bool active) {
  switch (label) {
    case 'Tab':
      return const Color(0xFFF97316); // orange
    case 'Caps':
      return active ? const Color(0xFF4C1D95) : const Color(0xFF6D28D9); // purple (darker when active)
    case 'Shift':
      return active ? const Color(0xFFDB2777) : const Color(0xFFEC4899); // pink (darker when active)
    case 'Enter':
      return const Color(0xFF86EFAC); // light green
    case '⌫':
      return const Color(0xFFEF4444); // red
    case 'Del':
      return const Color(0xFF7C2B12); // brown
    case 'Space':
      return const Color(0xFF06B6D4); // cyan
    // make home-row keys slightly darker to highlight touch points
    case 'a':
    case 's':
    case 'd':
    case 'f':
    case 'j':
    case 'k':
    case 'l':
    case ';':
      return const Color(0xFF9E9E9E);
    default:
      return const Color(0xFFBDBDBD); // default grey
  }
}

const Map<String, String> _shiftMap = {
  '`': '~',
  '1': '!',
  '2': '@',
  '3': '#',
  '4': r'$',
  '5': '%',
  '6': '^',
  '7': '&',
  '8': '*',
  '9': '(',
  '0': ')',
  '-': '_',
  '=': '+',
  '[': '{',
  ']': '}',
  '\\': '|',
  ';': ':',
  "'": '"',
  ',': '<',
  '.': '>',
  '/': '?',
};

String _displayLabel(String label, bool shiftActive, bool capsLock) {
  if (label.length == 1 && RegExp(r'[a-zA-Z]').hasMatch(label)) {
    final makeUpper = capsLock ^ shiftActive;
    return makeUpper ? label.toUpperCase() : label.toLowerCase();
  }
  if (shiftActive && _shiftMap.containsKey(label)) return _shiftMap[label]!;
  return label;
}

enum RemoteStatus { disconnected, connecting, connected, failed }

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Remote Keyboard',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
      ),
      home: const RemoteKeyboardPage(),
    );
  }
}

class RemoteKeyboardPage extends StatefulWidget {
  const RemoteKeyboardPage({super.key});

  @override
  State<RemoteKeyboardPage> createState() => _RemoteKeyboardPageState();
}

class _RemoteKeyboardPageState extends State<RemoteKeyboardPage> {
  final TextEditingController _hostController = TextEditingController(
    text: '192.168.1.10',
  );
  final TextEditingController _portController = TextEditingController(
    text: '5050',
  );
  final List<String> _recentInput = [];

  Socket? _socket;
  RemoteStatus _status = RemoteStatus.disconnected;
  String _statusMessage = 'Not connected';
  bool _shiftActive = false;
  bool _capsLock = false;
  // scrolling is always disabled by design

  @override
  void dispose() {
    _disconnect();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    if (host.isEmpty || port == null) {
      setState(() {
        _status = RemoteStatus.failed;
        _statusMessage = 'Enter a valid host and port';
      });
      return;
    }

    await _disconnect();
    setState(() {
      _status = RemoteStatus.connecting;
      _statusMessage = 'Connecting to $host:$port';
    });

    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
      socket.done.then((_) {
        if (!mounted || _socket != socket) return;
        setState(() {
          _socket = null;
          _status = RemoteStatus.disconnected;
          _statusMessage = 'Remote disconnected';
        });
      });
      setState(() {
        _socket = socket;
        _status = RemoteStatus.connected;
        _statusMessage = 'Connected to $host:$port';
      });
      _sendEvent({'type': 'hello', 'app': 'remote_keyboard'});
    } on Object catch (e, st) {
      if (!mounted) return;
      final msg = 'Connection failed: ${e.runtimeType}: $e';
      setState(() {
        _socket = null;
        _status = RemoteStatus.failed;
        _statusMessage = msg;
      });
      debugPrint('Connection failed: $e');
      debugPrint('$st');
      // show full exception and stack trace so user can copy details
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Connection Error'),
          content: SingleChildScrollView(
            child: SelectableText('$e\n\n$st'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _disconnect() async {
    final s = _socket;
    _socket = null;
    if (s != null) await s.close();
  }

  void _sendEvent(Map<String, Object?> event) {
    final s = _socket;
    if (s == null) {
      HapticFeedback.selectionClick();
      return;
    }
    s.writeln(jsonEncode(event));
  }

  void _recordInput(String value) {
    setState(() {
      _recentInput.add(value);
      if (_recentInput.length > 80) {
        _recentInput.removeRange(0, _recentInput.length - 80);
      }
    });
  }

  void _recordBackspace() {
    setState(() {
      if (_recentInput.isNotEmpty) _recentInput.removeLast();
    });
  }

  void _typeText(String value) {
    // handle modifier and control keys
    if (value == 'Shift') {
      setState(() => _shiftActive = true);
      return;
    }
    if (value == 'Caps') {
      setState(() => _capsLock = !_capsLock);
      return;
    }
    if (value == 'Backspace') {
      _recordBackspace();
      _sendEvent({'type': 'key', 'key': 'backspace'});
      return;
    }
    if (value == 'Delete') {
      _sendEvent({'type': 'key', 'key': 'delete'});
      return;
    }
    if (value == 'Tab') {
      _recordInput('\t');
      // send as a key event so remote can handle it as a control key
      _sendEvent({'type': 'key', 'key': 'tab'});
      setState(() => _shiftActive = false);
      return;
    }
    if (value == 'Enter') {
      _recordInput('\n');
      // send as a key event so remote can handle it as Enter
      _sendEvent({'type': 'key', 'key': 'enter'});
      setState(() => _shiftActive = false);
      return;
    }

    // printable character
    String out = value;
    if (value.length == 1 && RegExp(r'[a-zA-Z]').hasMatch(value)) {
      final makeUpper = _capsLock ^ _shiftActive;
      out = makeUpper ? value.toUpperCase() : value.toLowerCase();
    } else if (_shiftActive && _shiftMap.containsKey(value)) {
      out = _shiftMap[value]!;
    }
    _recordInput(out);
    _sendEvent({'type': 'text', 'value': out});
    if (_shiftActive) setState(() => _shiftActive = false);
  }

  // Preview text removed (no UI). Recent input still recorded internally.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              _ConnectionBar(
                hostController: _hostController,
                portController: _portController,
                status: _status,
                message: _statusMessage,
                onConnect: _connect,
                onDisconnect: () async {
                  await _disconnect();
                  if (!mounted) return;
                  setState(() {
                    _status = RemoteStatus.disconnected;
                    _statusMessage = 'Not connected';
                  });
                },
              ),
              const SizedBox(height: 10),
              // scrolling disabled
              Expanded(
                child: _KeyboardSurface(
                  onKeyPressed: (k) => _typeText(k),
                  shiftActive: _shiftActive,
                  capsLock: _capsLock,
                  scrollEnabled: false,
                  onShiftLongPressStart: () =>
                    setState(() => _shiftActive = true),
                  onShiftLongPressEnd: () =>
                    setState(() => _shiftActive = false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionBar extends StatelessWidget {
  final TextEditingController hostController;
  final TextEditingController portController;
  final RemoteStatus status;
  final String message;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const _ConnectionBar({
    required this.hostController,
    required this.portController,
    required this.status,
    required this.message,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final connected = status == RemoteStatus.connected;
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1B241E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2F4036)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: connected
                    ? const Color(0xFF34D399)
                    : const Color(0xFF94A3B8),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: TextField(
                controller: hostController,
                enabled: !connected,
                keyboardType: TextInputType.url,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Device IP',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 104,
              child: TextField(
                controller: portController,
                enabled: !connected,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Port',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 140,
              height: 48,
              child: FilledButton.icon(
                onPressed: connected ? onDisconnect : onConnect,
                icon: Icon(
                  connected
                      ? Icons.link_off_rounded
                      : Icons.settings_input_antenna_rounded,
                ),
                label: Text(connected ? 'Disconnect' : 'Connect'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: connected ? colorScheme.primary : Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Preview strip removed — input is still recorded internally but no longer shown.

class _KeyboardSurface extends StatelessWidget {
  final ValueChanged<String> onKeyPressed;
  final bool shiftActive;
  final bool capsLock;
  final bool scrollEnabled;
  final VoidCallback? onShiftLongPressStart;
  final VoidCallback? onShiftLongPressEnd;
  const _KeyboardSurface({
    required this.onKeyPressed,
    this.shiftActive = false,
    this.capsLock = false,
    this.scrollEnabled = false,
    this.onShiftLongPressStart,
    this.onShiftLongPressEnd,
  });

  static double _mmToLogicalPx(double mm) => mm * 5.75;

  @override
  Widget build(BuildContext context) {
    final width = _mmToLogicalPx(17.32);
    final height = _mmToLogicalPx(20.0);

    // spacing between adjacent keys (logical px). Edit this to change gap.
    final gap = _mmToLogicalPx(0);
    // (per-row shifts declared below)

    final rightLabels = ['w', 'e', '5', '6', 'i', 'o', 'p', '[', ']'];
    final secondRowLabels = [
      'Caps',
      'a',
      's',
      'd',
      'r',
      'y',
      'u',
      'k',
      'l',
      ';',
      "'",
    ];
    final thirdRowLabels = [
      'Shift',
      'z',
      'x',
      'c',
      'f',
      't',
      'h',
      'j',
      ',',
      '.',
      '/',
      'Shift',
    ];
    final fourthRowLabels = ['v', 'g', 'b', 'n', 'm'];
    // additional bottom row: ` 1 2 3 4 - = 7 8 9 0
    final newRowLabels = [
      '`',
      '1',
      '2',
      '3',
      '4',
      '-',
      '=',
      '7',
      '8',
      '9',
      '0',
    ];
    // shift for the second row (logical px). Edit to move row horizontally.
    final secondRowShift = 21.0;
    // per-row vertical shifts (logical px). Positive moves down.
    final rowVerticalShift = 100.0;
    final secondRowVerticalShift = 62.0;
    final thirdRowVerticalShift = 24.0;
    final fourthRowVerticalShift = -14.0;
    final fifthRowVerticalShift = -465.0;
    // per-row horizontal shifts (logical px)
    final rowShift = 70.0; // first row
    final thirdRowShift = -29.0;
    final fourthRowShift = -29.0;
    final fifthRowShift = 20.0;
    // spacebar shifts
    final spacebarShift = -29.0;
    final spacebarVerticalShift = -178.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFDCE7DF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        physics: scrollEnabled
            ? const AlwaysScrollableScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.translate(
                offset: Offset(rowShift, rowVerticalShift),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // tab key left of q
                    Transform.translate(
                      offset: Offset(0.0, 0.0),
                      child: _HexKey(
                        width: width,
                        height: height,
                        label: 'Tab',
                        displayLabel: _displayLabel('Tab', shiftActive, capsLock),
                        onPressed: () => onKeyPressed('Tab'),
                      ),
                    ),
                    SizedBox(width: gap),
                    // first key (q)
                    Transform.translate(
                      offset: Offset(0.0, 0.0),
                      child: _HexKey(
                        width: width,
                        height: height,
                        label: 'q',
                        displayLabel: _displayLabel('q', shiftActive, capsLock),
                        onPressed: () => onKeyPressed('q'),
                      ),
                    ),
                    // gap before right-side keys
                    SizedBox(width: gap),
                    // right-side keys with overlap applied to all but the first of that group
                    for (var i = 0; i < rightLabels.length; i++) ...[
                      Transform.translate(
                        offset: Offset(0.0, 0.0),
                        child: _HexKey(
                          width: width,
                          height: height,
                          label: rightLabels[i],
                          displayLabel: _displayLabel(rightLabels[i], shiftActive, capsLock),
                          onPressed: () => onKeyPressed(rightLabels[i]),
                        ),
                      ),
                      if (i != rightLabels.length - 1) SizedBox(width: gap),
                    ],
                    // small gap then a left-half hex key for backslash (no right half)
                    SizedBox(width: gap),
                    Transform.translate(
                      offset: Offset(0.0, 0.0),
                      child: _HalfOnlyHexKey(
                          width: width,
                          height: height,
                          label: '\\',
                          displayLabel: _displayLabel('\\', shiftActive, capsLock),
                          onPressed: () => onKeyPressed('\\'),
                          left: true,
                          rotation: math.pi / 6,
                          cutAngle: -math.pi / 6,
                        ),
                    ),
                  ],
                ),
              ),

              // small vertical gap between rows
              SizedBox(height: _mmToLogicalPx(1.0)),

              // second row (a s d r y u k l ; ')
              Transform.translate(
                offset: Offset(secondRowShift, secondRowVerticalShift),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < secondRowLabels.length; i++) ...[
                      Transform.translate(
                        offset: Offset(0.0, 0.0),
                        child: secondRowLabels[i] == 'Caps'
                            ? _HexKey(
                                width: width,
                                height: height,
                                label: 'Caps',
                                displayLabel: _displayLabel('Caps', shiftActive, capsLock),
                                onPressed: () => onKeyPressed('Caps'),
                                active: capsLock,
                              )
                            : _HexKey(
                                width: width,
                                height: height,
                                label: secondRowLabels[i],
                                displayLabel: _displayLabel(secondRowLabels[i], shiftActive, capsLock),
                                onPressed: () =>
                                    onKeyPressed(secondRowLabels[i]),
                              ),
                      ),
                      if (i != secondRowLabels.length - 1) SizedBox(width: gap),
                    ],
                    // Enter key to the right of the apostrophe
                    SizedBox(width: gap),
                    Transform.translate(
                      offset: Offset(0.0, 0.0),
                      child: _HexKey(
                          width: width,
                          height: height,
                          label: 'Enter',
                          displayLabel: _displayLabel('Enter', shiftActive, capsLock),
                          onPressed: () => onKeyPressed('Enter'),
                        ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: _mmToLogicalPx(1.0)),
              // third row (z x c f t h j , . /)
              Transform.translate(
                offset: Offset(thirdRowShift, thirdRowVerticalShift),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < thirdRowLabels.length; i++) ...[
                      Transform.translate(
                        offset: Offset(0.0, 0.0),
                        child: thirdRowLabels[i] == 'Shift'
                            ? _HexKey(
                                width: width,
                                height: height,
                                label: 'Shift',
                                displayLabel: _displayLabel('Shift', shiftActive, capsLock),
                                onPressed: () => onKeyPressed('Shift'),
                                active: shiftActive,
                                onLongPressStartCallback: onShiftLongPressStart,
                                onLongPressEndCallback: onShiftLongPressEnd,
                              )
                            : _HexKey(
                                width: width,
                                height: height,
                                label: thirdRowLabels[i],
                                displayLabel: _displayLabel(thirdRowLabels[i], shiftActive, capsLock),
                                onPressed: () =>
                                    onKeyPressed(thirdRowLabels[i]),
                              ),
                      ),
                      if (i != thirdRowLabels.length - 1) SizedBox(width: gap),
                    ],
                  ],
                ),
              ),

              SizedBox(height: _mmToLogicalPx(1.0)),
              // fourth row (v g b n m)
              Transform.translate(
                offset: Offset(fourthRowShift, fourthRowVerticalShift),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < fourthRowLabels.length; i++) ...[
                      Transform.translate(
                        offset: Offset(0.0, 0.0),
                        child: _HexKey(
                          width: width,
                          height: height,
                          label: fourthRowLabels[i],
                          displayLabel: _displayLabel(fourthRowLabels[i], shiftActive, capsLock),
                          onPressed: () => onKeyPressed(fourthRowLabels[i]),
                        ),
                      ),
                      if (i != fourthRowLabels.length - 1) SizedBox(width: gap),
                    ],
                  ],
                ),
              ),

              SizedBox(height: _mmToLogicalPx(1.0)),
              // fifth row (` 1 2 3 4 - = 7 8 9 0)
              Transform.translate(
                offset: Offset(fifthRowShift, fifthRowVerticalShift),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // build row, but merge '-' and '=' into a single split key
                    () {
                      final widgets = <Widget>[];
                      // Explicitly add the first key (backtick) to avoid
                      // any indexing or merge-edge cases.
                      if (newRowLabels.isNotEmpty) {
                        widgets.add(
                          Transform.translate(
                            offset: Offset(0.0, 0.0),
                            child: _HexKey(
                                      width: width,
                                      height: height,
                                      label: newRowLabels[0],
                                      displayLabel: _displayLabel(newRowLabels[0], shiftActive, capsLock),
                                      onPressed: () => onKeyPressed('`'),
                                    ),
                          ),
                        );
                        if (newRowLabels.length > 1) widgets.add(SizedBox(width: gap));
                      }
                      for (var i = 1; i < newRowLabels.length;) {
                        if (newRowLabels[i] == '-' &&
                            i + 1 < newRowLabels.length &&
                            newRowLabels[i + 1] == '=') {
                          widgets.add(
                            Transform.translate(
                              offset: Offset(0.0, 0.0),
                              child: _SplitHexKey(
                                width: width,
                                height: height,
                                leftLabel: '-',
                                rightLabel: '=',
                                leftDisplayLabel: _displayLabel('-', shiftActive, capsLock),
                                rightDisplayLabel: _displayLabel('=', shiftActive, capsLock),
                                onPressed: (s) => onKeyPressed(s),
                                rotation: math.pi / 6,
                                cutAngle: -math.pi / 6,
                              ),
                            ),
                          );
                          i += 2;
                        } else {
                          final label = newRowLabels[i];
                          widgets.add(
                            Transform.translate(
                              offset: Offset(0.0, 0.0),
                              child: _HexKey(
                                width: width,
                                height: height,
                                label: label,
                                displayLabel: _displayLabel(label, shiftActive, capsLock),
                                onPressed: () => onKeyPressed(label),
                              ),
                            ),
                          );
                          i += 1;
                        }
                        if (i < newRowLabels.length) widgets.add(SizedBox(width: gap));
                      }
                      // append Backspace and Delete keys after the row
                      widgets.add(SizedBox(width: gap));
                      widgets.add(
                        Transform.translate(
                          offset: Offset(0.0, 0.0),
                          child: _HexKey(
                            width: width,
                            height: height,
                            label: '⌫',
                            displayLabel: _displayLabel('⌫', shiftActive, capsLock),
                            onPressed: () => onKeyPressed('Backspace'),
                            repeatOnLongPress: true,
                          ),
                        ),
                      );
                      widgets.add(SizedBox(width: gap));
                      widgets.add(
                        Transform.translate(
                          offset: Offset(0.0, 0.0),
                          child: _HexKey(
                            width: width,
                            height: height,
                            label: 'Del',
                            displayLabel: _displayLabel('Del', shiftActive, capsLock),
                            onPressed: () => onKeyPressed('Delete'),
                          ),
                        ),
                      );
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: widgets,
                      );
                    }(),
                  ],
                ),
              ),
              // space before spacebar
              SizedBox(height: _mmToLogicalPx(2.0)),
              // Large spacebar composed of multiple hex keys (shiftable)
              Transform.translate(
                offset: Offset(spacebarShift, spacebarVerticalShift),
                child: Center(
                  child: Builder(
                    builder: (context) {
                      final int nHex = 6; // removed rightmost hexagon
                      final totalWidth = width * nHex + gap * (nHex - 1);
                      final rectHeight =
                          height * 0.75; // rectangle covers bottom -> 3/4 up
                      return SizedBox(
                        width: totalWidth,
                        height: height,
                        child: _SpacebarComposite(
                          width: totalWidth,
                          height: height,
                          nHex: nHex,
                          gap: gap,
                          rectHeight: rectHeight,
                          onSpace: () => onKeyPressed(' '),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HexKey extends StatefulWidget {
  final double width;
  final double height;
  final String label;
  final String? displayLabel;
  final VoidCallback onPressed;
  final bool repeatOnLongPress;
  final bool active;
  final VoidCallback? onLongPressStartCallback;
  final VoidCallback? onLongPressEndCallback;

  const _HexKey({
    required this.width,
    required this.height,
    required this.label,
    required this.onPressed,
    this.displayLabel,
    this.repeatOnLongPress = false,
    this.active = false,
    this.onLongPressStartCallback,
    this.onLongPressEndCallback,
  });

  @override
  State<_HexKey> createState() => _HexKeyState();
}

class _HexKeyState extends State<_HexKey> {
  Timer? _repeatTimer;

  void _startRepeat() {
    if (!widget.repeatOnLongPress) return;
    _repeatTimer?.cancel();
    // initial delay then repeat
    _repeatTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      widget.onPressed();
    });
  }

  void _stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rotation = math.pi / 6; // 30deg
    final bg = _keyBackgroundColor(widget.label, widget.active);
    final textColor = widget.active
        ? const Color(0xFF052014)
        : const Color(0xFF111A14);
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: GestureDetector(
        onTap: widget.onPressed,
        onLongPressStart: (_) {
          widget.onLongPressStartCallback?.call();
          _startRepeat();
        },
        onLongPressEnd: (_) {
          widget.onLongPressEndCallback?.call();
          _stopRepeat();
        },
        child: Transform.rotate(
          angle: rotation,
          child: ClipPath(
            clipper: _HexagonClipper(),
            child: Builder(
              builder: (context) {
                Alignment labelAlignment = Alignment.center;
                EdgeInsetsGeometry padding = EdgeInsets.zero;
                if (widget.label == '-') {
                  labelAlignment = Alignment.centerLeft;
                  padding = EdgeInsets.only(
                    left: widget.width * _kLabelPaddingFactor,
                  );
                } else if (widget.label == '=') {
                  labelAlignment = Alignment.centerRight;
                  padding = EdgeInsets.only(
                    right: widget.width * _kLabelPaddingFactor,
                  );
                }
                return Container(
                  color: bg,
                  alignment: labelAlignment,
                  padding: padding,
                  child: Transform.rotate(
                      angle: -rotation,
                      child: Text(
                        widget.displayLabel ?? widget.label,
                        style: TextStyle(
                          fontSize: _kLabelFontSize,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                    ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// removed _HalfHexKey (replaced by _HalfOnlyHexKey below)

class _HalfHexagonClipper extends CustomClipper<Path> {
  final bool left;
  final double cutAngle; // radians; 0 = vertical axis
  _HalfHexagonClipper(this.left, [this.cutAngle = 0.0]);

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final s = math.min(w / 2.0, h / math.sqrt(3.0));
    final r = s;
    final pts = <Offset>[];
    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3;
      pts.add(Offset(cx + r * math.cos(angle), cy + r * math.sin(angle)));
    }

    final pathPts = <Offset>[];
    final axis = Offset(math.cos(cutAngle), math.sin(cutAngle));
    for (var i = 0; i < 6; i++) {
      final p1 = pts[i];
      final p2 = pts[(i + 1) % 6];
      final v1 = p1 - Offset(cx, cy);
      final v2 = p2 - Offset(cx, cy);
      final d1 = v1.dx * axis.dx + v1.dy * axis.dy;
      final d2 = v2.dx * axis.dx + v2.dy * axis.dy;
      if ((left && d1 <= 0) || (!left && d1 >= 0)) {
        pathPts.add(p1);
      }
      if (d1 * d2 < 0) {
        final t = d1 / (d1 - d2);
        final ix = p1.dx + t * (p2.dx - p1.dx);
        final iy = p1.dy + t * (p2.dy - p1.dy);
        pathPts.add(Offset(ix, iy));
      } else if (d1 == 0) {
        pathPts.add(p1);
      }
    }

    final path = Path();
    if (pathPts.isEmpty) {
      if (left) {
        path.addRect(Rect.fromLTWH(0, 0, cx, h));
      } else {
        path.addRect(Rect.fromLTWH(cx, 0, w - cx, h));
      }
      return path;
    }

    path.moveTo(pathPts[0].dx, pathPts[0].dy);
    for (var i = 1; i < pathPts.length; i++) {
      path.lineTo(pathPts[i].dx, pathPts[i].dy);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _SplitHexKey extends StatelessWidget {
  final double width;
  final double height;
  final String leftLabel;
  final String rightLabel;
  final String? leftDisplayLabel;
  final String? rightDisplayLabel;
  final ValueChanged<String> onPressed;
  final double rotation; // radians
  final double cutAngle; // axis angle for dividing line (0 = vertical)

  const _SplitHexKey({
    required this.width,
    required this.height,
    required this.leftLabel,
    required this.rightLabel,
    required this.onPressed,
    this.leftDisplayLabel,
    this.rightDisplayLabel,
    this.rotation = math.pi / 6,
    this.cutAngle = -math.pi / 6,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          final local = details.localPosition;
          final center = Offset(width / 2, height / 2);
          final rel = local - center;
          final ax = Offset(math.cos(cutAngle), math.sin(cutAngle));
          final dot = rel.dx * ax.dx + rel.dy * ax.dy;
          if (dot <= 0) {
            onPressed(leftLabel);
          } else {
            onPressed(rightLabel);
          }
        },
        child: Transform.rotate(
          angle: rotation,
            child: ClipPath(
          clipper: _HexagonClipper(),
          child: Container(
              color: _keyBackgroundColor(leftLabel, false),
              child: Stack(
                  children: [
                    // Two centered halves for labels
                    Row(
                      children: [
                        Expanded(
                          child: Center(
                            child: Transform.rotate(
                              angle: -rotation,
                              child: Text(
                                leftDisplayLabel ?? leftLabel,
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF111A14),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Center(
                              child: Transform.rotate(
                                angle: -rotation,
                                child: Text(
                                  rightDisplayLabel ?? rightLabel,
                                  style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF111A14),
                                  ),
                                ),
                              ),
                          ),
                        ),
                      ],
                    ),
                    // no seam outline (keeps a clean split appearance)
                  ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HalfOnlyHexKey extends StatelessWidget {
  final double width;
  final double height;
  final String label;
  final String? displayLabel;
  final VoidCallback onPressed;
  final bool left;
  final double rotation;
  final double cutAngle;

  const _HalfOnlyHexKey({
    required this.width,
    required this.height,
    required this.label,
    required this.onPressed,
    this.left = true,
    this.rotation = math.pi / 6,
    this.cutAngle = -math.pi / 6,
    this.displayLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: GestureDetector(
        onTap: onPressed,
        child: Transform.rotate(
          angle: rotation,
            child: ClipPath(
            clipper: _HalfHexagonClipper(left, cutAngle),
            child: Container(
              color: _keyBackgroundColor(label, false),
              alignment: left ? Alignment.centerLeft : Alignment.centerRight,
              padding: left
                  ? EdgeInsets.only(left: width * 0.12)
                  : EdgeInsets.only(right: width * 0.12),
              child: Transform.rotate(
                angle: -rotation,
                child: Text(
                  displayLabel ?? label,
                  style: TextStyle(
                    fontSize: _kLabelFontSize,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111A14),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HexVisual extends StatelessWidget {
  final double width;
  final double height;
  final String label;
  final Color color;
  const _HexVisual({
    required this.width,
    required this.height,
    this.label = '',
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    const rotation = math.pi / 6; // 30deg
    return SizedBox(
      width: width,
      height: height,
      child: Transform.rotate(
        angle: rotation,
          child: ClipPath(
          clipper: _HexagonClipper(),
          child: Container(
            color: color,
            alignment: Alignment.center,
            child: Transform.rotate(
              angle: -rotation,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: _kLabelFontSize,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF111A14),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpacebarComposite extends StatefulWidget {
  final double width;
  final double height;
  final int nHex;
  final double gap;
  final double rectHeight;
  final VoidCallback onSpace;

  const _SpacebarComposite({
    required this.width,
    required this.height,
    required this.nHex,
    required this.gap,
    required this.rectHeight,
    required this.onSpace,
  });

  @override
  State<_SpacebarComposite> createState() => _SpacebarCompositeState();
}

class _SpacebarCompositeState extends State<_SpacebarComposite> {
  Timer? _repeatTimer;

  void _startRepeat() {
    _repeatTimer?.cancel();
    widget.onSpace();
    _repeatTimer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => widget.onSpace(),
    );
  }

  void _stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalWidth = widget.width;
    final rectHeight = widget.rectHeight;
    final nHex = widget.nHex;
    final gap = widget.gap;

    return GestureDetector(
      onTap: widget.onSpace,
      onLongPressStart: (_) => _startRepeat(),
      onLongPressEnd: (_) => _stopRepeat(),
      child: SizedBox(
        width: totalWidth,
        height: widget.height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List<Widget>.generate(nHex * 2 - 1, (index) {
                if (index.isOdd) return SizedBox(width: gap);
                return _HexVisual(
                  width: widget.height * 0.866,
                  height: widget.height,
                  label: '',
                  color: _keyBackgroundColor('Space', false),
                );
              }),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: totalWidth - (widget.height * 0.866),
                height: rectHeight,
                decoration: BoxDecoration(color: _keyBackgroundColor('Space', false)),
                child: Center(
                  child: Text(
                    'Space',
                    style: TextStyle(
                      fontSize: _kLabelFontSize,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111A14),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HexagonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final s = math.min(w / 2.0, h / math.sqrt(3.0));
    final r = s;
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
