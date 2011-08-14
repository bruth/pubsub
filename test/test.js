test('Publisher', 7, function() {
  var hub, p;
  hub = new PubSub;
  hub.publish('foo', 1);
  hub.publish('foo', 2);
  p = hub.publish('foo', 3);
  equals(p.messages.length, 3);
  equals(p.tip().content[0], 3);
  p.active = false;
  ok(!hub.publish('foo', 'nope'));
  equals(p.messages.length, 3, 'not recorded');
  p.active = true;
  ok(hub.publish('foo', 'yep'));
  p = hub.publish('bar', 1, 2, 3, 4);
  equals(p.messages.length, 1);
  p = hub.publish('baz', function() {});
  return equals(p.messages.length, 1);
});
test('Subscriber', 6, function() {
  var hub, output, s1, s2;
  hub = new PubSub;
  output = null;
  s1 = hub.subscribe('foo', function(msg) {
    return output = msg;
  });
  hub.subscribe('foo', (function(msg) {
    return output = "" + this + " " + msg;
  }), 'goober');
  s2 = hub.subscribe('foo', function(msg) {
    return output = "moto " + msg;
  });
  ok(hub.publishers.foo, 'a new topic has been added');
  equals(s1.publisher.subscribers.length, 3, 'the subscriber has been added');
  equals(output, null, 'nothing changed yet');
  s2.online = false;
  hub.publish('foo', 4);
  ok(s1.tip);
  ok(!s2.tip);
  return equals(output, 'goober 4');
});
test('Subscribe - late', 6, function() {
  var hub, output, p3, sub1, sub2, sub3;
  hub = new PubSub;
  output = 0;
  hub.publish('foo');
  hub.publish('foo');
  p3 = hub.publish('foo');
  sub1 = hub.subscribe('foo', function() {
    return output++;
  });
  equals(output, 3, 'all history up to this point');
  equals(sub1.tip, p3.tip(), 'last pub is referenced');
  sub2 = hub.subscribe('foo', function() {
    return output++;
  }, 'tip');
  equals(output, 4, 'only the tip of the history was executed');
  equals(sub2.tip, p3.tip(), 'last pub is referenced');
  sub3 = hub.subscribe('foo', function() {
    return output++;
  }, false);
  equals(output, 4, 'none of the history is applied');
  return equals(sub3.tip, null, 'no pub has been applied');
});
test('Unsubscribe & Re-subscribe', 3, function() {
  var hub, output, s1;
  hub = new PubSub;
  output = 0;
  s1 = hub.subscribe('foo', function() {
    return output++;
  });
  hub.publish('foo');
  hub.publish('foo');
  equals(output, 2, '2 pubs');
  hub.unsubscribe(s1);
  hub.publish('foo');
  hub.publish('foo');
  equals(output, 2, 'still 2 pubs');
  hub.subscribe(s1);
  return equals(output, 4, 'resumed to 4 pubs');
});
