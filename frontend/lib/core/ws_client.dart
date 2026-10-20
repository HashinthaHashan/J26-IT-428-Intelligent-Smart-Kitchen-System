import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'config.dart';

enum LiveConnectionState { connecting, connected, reconnecting, disconnected }

class LiveFrame {
  const LiveFrame({required this.type, required this.data});

  factory LiveFrame.fromJson(Map<String, dynamic> json) => LiveFrame(
        type: json['type'] as String,
        data: Map<String, dynamic>.from(json['data'] as Map),
      );

  final String type;
  final Map<String, dynamic> data;
}

class WsClient {
  WsClient({Uri? uri}) : _uri = uri ?? AppConfig.liveUri;

  final Uri _uri;
  final _events = StreamController<LiveFrame>.broadcast();
  final _states = StreamController<LiveConnectionState>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  Timer? _retryTimer;
  bool _closed = false;
  int _attempt = 0;

  Stream<LiveFrame> get events => _events.stream;
  Stream<LiveConnectionState> get states => _states.stream;

  void connect() {
    if (_closed || _channel != null) return;
    _states.add(_attempt == 0
        ? LiveConnectionState.connecting
        : LiveConnectionState.reconnecting);
    final channel = WebSocketChannel.connect(_uri);
    _channel = channel;
    channel.ready.then((_) {
      if (_closed || _channel != channel) return;
      _attempt = 0;
      _states.add(LiveConnectionState.connected);
    }).catchError((Object _) => _scheduleReconnect(channel));
    _subscription = channel.stream.listen(
      (message) {
        try {
          final decoded = jsonDecode(message.toString());
          if (decoded is Map<String, dynamic>) {
            _events.add(LiveFrame.fromJson(decoded));
          }
        } catch (_) {
          // Ignore malformed frames; the next valid frame remains usable.
        }
      },
      onError: (_) => _scheduleReconnect(channel),
      onDone: () => _scheduleReconnect(channel),
      cancelOnError: true,
    );
  }

  void _scheduleReconnect(WebSocketChannel source) {
    if (_closed || _channel != source) return;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _states.add(LiveConnectionState.reconnecting);
    final exponent = _attempt > 5 ? 5 : _attempt;
    final seconds = exponent == 5 ? 30 : 1 << exponent;
    _attempt++;
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: seconds), connect);
  }

  Future<void> dispose() async {
    _closed = true;
    _retryTimer?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
    await _events.close();
    await _states.close();
  }
}

final wsClientProvider = Provider<WsClient>((ref) {
  final client = WsClient()..connect();
  ref.onDispose(client.dispose);
  return client;
});

final liveFrameProvider = StreamProvider<LiveFrame>((ref) {
  return ref.watch(wsClientProvider).events;
});

final liveConnectionProvider = StreamProvider<LiveConnectionState>((ref) async* {
  final client = ref.watch(wsClientProvider);
  yield LiveConnectionState.connecting;
  yield* client.states;
});
