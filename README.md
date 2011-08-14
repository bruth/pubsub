PubSub
======

* Annotated source code: http://bruth.github.com/pubsub/docs/pubsub.html
* Tests: http://bruth.github.com/pubsub/test/index.html

PubSub is a simple library for creating pub/sub _hubs_. A hub is composed of
**publishers** each of which are uniquely identified by a *topic*. Each
publisher can have one more more **subscribers**. The hub provides a
simple API for publishing messages on behalf of the publishers.

```javascript
var hub = new PubSub;
var output;

hub.subscribe('foo', function(msg) {
    output = msg;
});

hub.publish('foo', 'hello world!');
output; // 'hello world'
```

Late Subscribers
----------------
PubSub has support for _catching up_ late subscribers due to one reason
(async subscription) or another. The default behavior is to iterate over
the message queue and send each message to the the subscriber.

```javascript
var hub = new PubSub;
var output;

// a publish occurred before any subscribers were defined
hub.publish('foo', 'hello world!');

hub.subscribe('foo', function(msg) {
    output = msg;
});

output; // 'hello world'
```

The ``migrate`` parameter supports ``true``, ``'tip'`` and ``false``. If
``false`` is passd, no messages in the publisher's queue will be applied to the
subscriber.

```javascript
var hub = new PubSub;
var output;

// a publish occurred before any subscribers were defined
hub.publish('foo', 'hello world!');

hub.subscribe('foo', function(msg) {
    output = msg;
}, false);

output; // undefined
```

Unsubscribing
-------------
When a subscription occurs, the new subscriber is returned. The instanced can
be passed in to temporarily unsubscribe (turn offline) or completely remove
the subscriber from the hub.

```javascript
var hub = new PubSub;
var output;

var sub = hub.subscribe('foo', function(msg) {
    output = msg;
});

hub.publish('foo', 'hello world!');
output; // 'hello world!'

hub.unsubscribe(sub);

hub.publish('foo', 'new message');
output; // 'hello world!', nothing changed

hub.subscribe(sub);
output; // 'new message', it caught back up

// completely removes it from the hub. the subscriber is no longer
hub.unsubscribe(sub, true);
```
