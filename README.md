# absinthe_socket_link

Dart library to interact with Absinthe Subscriptions over [Phoenix Channels](https://hexdocs.pm/phoenix/Phoenix.Channel.html#content).

This library uses [phoenix_socket](https://pub.dev/packages/phoenix_socket) for Phoenix Channel, making the API consistent across web and native environments.

## Usage

This is a simple implementation.

```dart
Link createGraphqlLink() async {
  final HttpLink httpLink = HttpLink("http://localhost/graphql");

  final phoenixSocket = PhoenixSocket(
    "ws://localhost/graphql/websocket",
    socketOptions: PhoenixSocketOptions(
      params: {"authorization": 'My Strong Token'},
    ),
  );

  final wsLink = AbsintheSocketLink(phoenixSocket);

  return Link.split(
    (request) => request.isSubscription,
    wsLink, httpLink,
  );
}
```
