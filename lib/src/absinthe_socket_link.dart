import 'dart:async';

import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';
import 'package:phoenix_socket/phoenix_socket.dart';

class AbsintheSocketLink extends Link {
  PhoenixChannel? _channel;
  final PhoenixSocket _socket;
  final String _absintheChannelName = '__absinthe__:control';
  final RequestSerializer _serializer;
  final ResponseParser _parser;

  AbsintheSocketLink(
    PhoenixSocket socket, {
    ResponseParser parser = const ResponseParser(),
    RequestSerializer serializer = const RequestSerializer(),
  })  : _socket = socket,
        _serializer = serializer,
        _parser = parser;

  void _connect() {
    if (_channel == null) {
      _channel = _socket.addChannel(topic: _absintheChannelName);
      _channel!.join();
      _channel!.socket.connect().ignore();
    }
  }

  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    assert(forward == null, '$this does not support a NextLink (got $forward)');
    _connect();

    StreamSubscription? closeSocketSubscription;
    StreamSubscription? openSocketSubscription;
    Function? onCancel;

    final streamController = StreamController<Response>(
      onCancel: () {
        closeSocketSubscription?.cancel();
        openSocketSubscription?.cancel();
        onCancel?.call(true);
      },
    );

    final payload = _serializer.serializeRequest(request);
    onCancel ??= _subscribe(streamController, payload);
    closeSocketSubscription = _channel?.socket.closeStream.listen((event) {
      onCancel?.call(false);
      onCancel = null;
    });

    openSocketSubscription = _channel?.socket.openStream.listen((event) async {
      onCancel ??= _subscribe(streamController, payload);
    });

    return streamController.stream;
  }

  @override
  Future<void> dispose() async {
    _channel?.close();
    await _channel?.leave().future;
    _channel = null;
  }

  Function([bool unsubscribe]) _subscribe(
    StreamController<Response> streamController,
    Map<String, dynamic> payload,
  ) {
    String? subscriptionId;
    StreamSubscription<Response>? streamSubscription;

    _channel?.push('doc', payload).future.then((pushResponse) {
      subscriptionId = pushResponse.response['subscriptionId'] as String?;

      if (subscriptionId != null) {
        streamSubscription = _channel?.socket
            .streamForTopic(subscriptionId!)
            .map((event) => _parser.parseResponse(event.payload!['result']))
            .listen(streamController.add, onError: streamController.addError);
        return;
      }

      if (pushResponse.isOk) {
        streamController.add(_parser.parseResponse(pushResponse.response));
      }

      if (pushResponse.isError) {
        streamController.addError(_parser.parseError(pushResponse.response));
      }
    });

    return ([bool unsubscribe = true]) async {
      await streamSubscription?.cancel();
      if (unsubscribe && subscriptionId != null) {
        _channel?.push('unsubscribe', {'subscriptionId': subscriptionId});
      }
      streamSubscription = null;
      subscriptionId = null;
    };
  }
}
