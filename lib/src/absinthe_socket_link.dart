import 'dart:async';

import 'package:graphql/client.dart';
import 'package:phoenix_socket/phoenix_socket.dart';

typedef ConnectionParams = Future<Map<String, String>> Function();

class AbsintheSocketLink extends Link {
  PhoenixChannel? _channel;
  final String _url;
  final ConnectionParams? _connectionParams;
  final String _absintheChannelName = '__absinthe__:control';

  final RequestSerializer _serializer;
  final ResponseParser _parser;

  AbsintheSocketLink(
    String url, {
    ConnectionParams? connectionParams,
    ResponseParser parser = const ResponseParser(),
    RequestSerializer serializer = const RequestSerializer(),
  })  : _url = url,
        _connectionParams = connectionParams,
        _serializer = serializer,
        _parser = parser;

  /// create a new phoenix socket from the given url,
  /// connect to it, and create a channel, and join it
  Future<PhoenixChannel> _createChannel() async {
    final socket = PhoenixSocket(
      _url,
      socketOptions: PhoenixSocketOptions(dynamicParams: _connectionParams),
    );
    await socket.connect();
    final channel = socket.addChannel(topic: _absintheChannelName);
    await channel.join().future;

    return channel;
  }

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    assert(forward == null, '$this does not support a NextLink (got $forward)');

    final payload = _serializer.serializeRequest(request);
    String? phoenixSubscriptionId;

    await _connectOrReconnect();

    final push = _channel!.push('doc', payload);
    final pushResponse = await push.future;

    phoenixSubscriptionId = pushResponse.response['subscriptionId'] as String?;

    if (phoenixSubscriptionId == null) {
      if (pushResponse.isOk) {
        yield _parser.parseResponse(pushResponse.response);
      } else if (pushResponse.isError) {
        yield* Stream.error(_parser.parseError(pushResponse.response));
      }
      return;
    }

    final subscriptionStream = _channel!.socket
        .streamForTopic(phoenixSubscriptionId)
        .map((event) => _parser.parseResponse(event.payload!['result']));

    try {
      yield* subscriptionStream;
    } finally {
      // Clean-up code when subscription is canceled
      _channel!
          .push('unsubscribe', {'subscriptionId': phoenixSubscriptionId})
          .future
          .ignore();
    }
  }

  Future<void> _connectOrReconnect() async {
    if (_channel != null && _channel?.state != PhoenixChannelState.closed) {
      return;
    }

    final newChannel = await _createChannel();
    await _close();
    _channel = newChannel;
  }

  Future<void> _close() async {
    await _channel?.leave().future;
    _channel?.close();
    _channel = null;
  }

  @override
  Future<void> dispose() => _close();
}
