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
the whole message history and send each message to the the subscriber.

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

The ``history`` parameter supports ``'full'`` and ``'tip'``. If any other
value is specified, none of the publisher's history will be applied.


History API
-----------
PubSub has a very simple history API with ``undo`` and ``redo`` methods.
For [idempotent][1] subscribers, only a single function is required to be
supplied (like the above example).

For non-idempotent subscribers, two handlers should be supplied representing the
``forwards`` and ``backwards`` operations. The below example shows this.

[1]: http://en.wikipedia.org/wiki/Idempotence

```javascript
var hub = new PubSub;

function Counter() {
    this.count = 0
    this.incr = function() {
        this.count++;
    }
    this.decr = function() {
        this.count--;
    }
}

var counter = new Counter;

hub.subscribe('click', counter.incr, counter.decr);

hub.publish('click');
hub.publish('click');
counter.count; // 2

hub.undo();
counter.count; // 1

hub.redo();
counter.count; // 2
```

If the history API is not used at all, the ``backwards`` is not necessary
regardless of the idempotency.

Unsubscribing
-------------
When a subscription occurs, a subscriber ID is returned which can
be used to reference the subscriber in the future. The ``sid`` can be passed
in to temporarily unsubscribe (or completely remove) the subscriber.

```javascript
var hub = new PubSub;
var output;

var sid1 = hub.subscribe('foo', function(msg) {
    output = msg;
});

hub.publish('foo', 'hello world!');
output; // 'hello world!'

hub.unsubscribe(sid1);

hub.publish('foo', 'new message');
output; // 'hello world!', nothing changed

hub.subscribe(sid);
output; // 'new message', it caught back up

// completely removes it from the hub. the sid is no longer valid
hub.unsubscribe(sid, true); 
```

If a publisher topic is passed into ``unsubscribe`` all messages for that
publisher are suspended. That is, any call to ``publish`` for the suspended
publisher will never be forwarded to it's subscribers.

As with the subscriber above, publishers can be completely removed from the
hub.

```javascript
var hub = new PubSub;
var output;

hub.subscribe('foo', function(msg) {
    output = msg;
});

hub.publish('foo', 'hello world!');
output; // 'hello world'

hub.unsubscribe('foo');

// no history is recorded while a publisher is unsubscribed
hub.publish('foo', 'new message');
output; // 'hello world!', nothing changed

hub.subscribe('foo');
output; // 'hello world!', still nothing changed

// completely removes it from the hub. the publisher and all of it's
// subscribers are removed from the hub.
hub.unsubscribe('foo', true); 
```
