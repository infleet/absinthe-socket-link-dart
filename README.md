# absinthe_socket_link

Dart library to interact with Absinthe Subscriptions over [Phoenix Channels](https://hexdocs.pm/phoenix/Phoenix.Channel.html#content).

This library uses [phoenix_socket](https://pub.dev/packages/phoenix_socket) for Phoenix Channel, making the API consistent across web and native environments.

## Usage

This is a simple implementation.

```dart
Link createGraphqlLink() async {
  final HttpLink httpLink = HttpLink("http://localhost/graphql");

  final wsLink = AbsintheSocketLink(
    "ws://localhost/graphql/websocket",
    connectionParams: () async {
      return {"authorization": 'My Strong Token'};
    },
  );

  return Link.split(
    (request) => request.isSubscription,
    wsLink, httpLink,
  );
}
```
