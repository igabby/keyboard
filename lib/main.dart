import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFF101511),
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
  bool _shiftEnabled = false;
  bool _numbersEnabled = false;

  static const List<String> _suggestions = [
    'Hello',
    'Thanks',
    'Yes',
    'No',
    'Flutter',
    'Keyboard',
  ];

  static const List<List<String>> _letterRows = [
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
  ];

  static const List<List<String>> _numberRows = [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['-', '/', ':', ';', '(', ')', r'$', '&', '@'],
    ['.', ',', '?', '!', "'", '"', '#', '+'],
  ];

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
    if (!mounted) {
      return;
    }
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
      if (!mounted) {
        await socket.close();
        return;
      }
      socket.done.then((_) {
        if (!mounted || _socket != socket) {
          return;
        }
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
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _socket = null;
        _status = RemoteStatus.failed;
        _statusMessage = 'Connection failed: $error';
      });
    }
  }

  Future<void> _disconnect() async {
    final socket = _socket;
    _socket = null;
    if (socket == null) {
      return;
    }
    await socket.close();
  }

  void _sendEvent(Map<String, Object?> event) {
    final socket = _socket;
    if (socket == null) {
      HapticFeedback.selectionClick();
      return;
    }
    socket.writeln(jsonEncode(event));
  }

  void _recordInput(String value) {
    setState(() {
      _recentInput.add(value);
      if (_recentInput.length > 80) {
        _recentInput.removeRange(0, _recentInput.length - 80);
      }
    });
  }

  void _typeText(String value) {
    _recordInput(value);
    _sendEvent({'type': 'text', 'value': value});
    if (_shiftEnabled && value.trim().isNotEmpty && !_numbersEnabled) {
      setState(() => _shiftEnabled = false);
    }
  }

  void _sendKey(String key) {
    _recordInput(_previewForKey(key));
    _sendEvent({'type': 'key', 'key': key});
  }

  String _previewForKey(String key) {
    switch (key) {
      case 'backspace':
        return '⌫';
      case 'enter':
        return '\n';
      case 'tab':
        return '⇥';
      case 'escape':
        return 'Esc';
      default:
        return key;
    }
  }

  String get _previewText {
    if (_recentInput.isEmpty) {
      return 'Remote input preview';
    }
    return _recentInput.join();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardRows = _numbersEnabled ? _numberRows : _letterRows;

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
                onDisconnect: () {
                  _disconnect();
                  setState(() {
                    _status = RemoteStatus.disconnected;
                    _statusMessage = 'Not connected';
                  });
                },
              ),
              const SizedBox(height: 10),
              _PreviewStrip(text: _previewText),
              const SizedBox(height: 10),
              _SuggestionBar(
                suggestions: _suggestions,
                onSelected: (suggestion) => _typeText('$suggestion '),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _KeyboardSurface(
                  rows: keyboardRows,
                  shiftEnabled: _shiftEnabled,
                  numbersEnabled: _numbersEnabled,
                  connected: _status == RemoteStatus.connected,
                  onKeyPressed: (key) {
                    final value = _shiftEnabled ? key.toUpperCase() : key;
                    _typeText(value);
                  },
                  onShiftPressed: () {
                    setState(() => _shiftEnabled = !_shiftEnabled);
                  },
                  onModePressed: () {
                    setState(() => _numbersEnabled = !_numbersEnabled);
                  },
                  onBackspacePressed: () => _sendKey('backspace'),
                  onSpacePressed: () => _typeText(' '),
                  onEnterPressed: () => _sendKey('enter'),
                  onTabPressed: () => _sendKey('tab'),
                  onEscapePressed: () => _sendKey('escape'),
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
            _StatusDot(status: status),
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
                onPressed: status == RemoteStatus.connecting
                    ? null
                    : connected
                    ? onDisconnect
                    : onConnect,
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

class _StatusDot extends StatelessWidget {
  final RemoteStatus status;

  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      RemoteStatus.connected => const Color(0xFF34D399),
      RemoteStatus.connecting => const Color(0xFFFBBF24),
      RemoteStatus.failed => const Color(0xFFF87171),
      RemoteStatus.disconnected => const Color(0xFF94A3B8),
    };

    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _PreviewStrip extends StatelessWidget {
  final String text;

  const _PreviewStrip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 56,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F2EC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        style: const TextStyle(
          color: Color(0xFF15221A),
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SuggestionBar extends StatelessWidget {
  final List<String> suggestions;
  final ValueChanged<String> onSelected;

  const _SuggestionBar({required this.suggestions, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: suggestions.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final suggestion = suggestions[index];
          return ActionChip(
            label: Text(suggestion),
            avatar: const Icon(Icons.bolt_rounded, size: 16),
            onPressed: () => onSelected(suggestion),
          );
        },
      ),
    );
  }
}

class _KeyboardSurface extends StatelessWidget {
  final List<List<String>> rows;
  final bool shiftEnabled;
  final bool numbersEnabled;
  final bool connected;
  final ValueChanged<String> onKeyPressed;
  final VoidCallback onShiftPressed;
  final VoidCallback onModePressed;
  final VoidCallback onBackspacePressed;
  final VoidCallback onSpacePressed;
  final VoidCallback onEnterPressed;
  final VoidCallback onTabPressed;
  final VoidCallback onEscapePressed;

  const _KeyboardSurface({
    required this.rows,
    required this.shiftEnabled,
    required this.numbersEnabled,
    required this.connected,
    required this.onKeyPressed,
    required this.onShiftPressed,
    required this.onModePressed,
    required this.onBackspacePressed,
    required this.onSpacePressed,
    required this.onEnterPressed,
    required this.onTabPressed,
    required this.onEscapePressed,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFDCE7DF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            for (final row in rows)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _KeyboardRow(
                    keys: row,
                    shiftEnabled: shiftEnabled,
                    numbersEnabled: numbersEnabled,
                    onKeyPressed: onKeyPressed,
                  ),
                ),
              ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _UtilityKey(
                      tooltip: numbersEnabled ? 'Letters' : 'Numbers',
                      label: numbersEnabled ? 'ABC' : '123',
                      onPressed: onModePressed,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _IconKey(
                      tooltip: 'Shift',
                      selected: shiftEnabled,
                      icon: Icons.keyboard_capslock_rounded,
                      onPressed: onShiftPressed,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _UtilityKey(
                      tooltip: 'Escape',
                      label: 'Esc',
                      onPressed: onEscapePressed,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _UtilityKey(
                      tooltip: 'Tab',
                      label: 'Tab',
                      onPressed: onTabPressed,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 5,
                    child: _UtilityKey(
                      tooltip: 'Space',
                      label: connected ? 'space' : 'space (offline preview)',
                      onPressed: onSpacePressed,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _IconKey(
                      tooltip: 'Enter',
                      icon: Icons.keyboard_return_rounded,
                      onPressed: onEnterPressed,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _IconKey(
                      tooltip: 'Backspace',
                      icon: Icons.backspace_outlined,
                      onPressed: onBackspacePressed,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyboardRow extends StatelessWidget {
  final List<String> keys;
  final bool shiftEnabled;
  final bool numbersEnabled;
  final ValueChanged<String> onKeyPressed;

  const _KeyboardRow({
    required this.keys,
    required this.shiftEnabled,
    required this.numbersEnabled,
    required this.onKeyPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final keyValue in keys) ...[
          Expanded(
            child: _KeyButton(
              label: shiftEnabled && !numbersEnabled
                  ? keyValue.toUpperCase()
                  : keyValue,
              onPressed: () => onKeyPressed(keyValue),
            ),
          ),
          if (keyValue != keys.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _KeyButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF111A14),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
        ),
        onPressed: onPressed,
        child: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
      ),
    );
  }
}

class _IconKey extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  const _IconKey({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: IconButton.filledTonal(
        tooltip: tooltip,
        isSelected: selected,
        selectedIcon: Icon(icon, size: 30),
        icon: Icon(icon, size: 30),
        onPressed: onPressed,
      ),
    );
  }
}

class _UtilityKey extends StatelessWidget {
  final String tooltip;
  final String label;
  final VoidCallback onPressed;

  const _UtilityKey({
    required this.tooltip,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.expand(
        child: FilledButton.tonal(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          onPressed: onPressed,
          child: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
        ),
      ),
    );
  }
}
