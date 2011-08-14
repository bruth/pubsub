var __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };
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
  }), null, 'goober');
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
test('Idempotent Undo/Redo', 11, function() {
  var hub, output;
  hub = new PubSub;
  output = void 0;
  hub.subscribe('foo', function(msg) {
    return output = msg;
  });
  hub.undo();
  equals(output, void 0, 'cannot go backward');
  hub.publish('foo', 'hello moto');
  equals(output, 'hello moto', 'updated');
  hub.undo();
  equals(output, void 0, 'handler called with no arguments');
  hub.redo();
  equals(output, 'hello moto', 'stays the same');
  hub.publish('foo', 'and again');
  equals(output, 'and again', 'updated');
  hub.undo();
  equals(output, 'hello moto', 'back 1');
  hub.redo();
  equals(output, 'and again', 'forward 1');
  hub.publish('foo', 'once more');
  equals(output, 'once more', 'updated');
  hub.undo();
  hub.undo();
  equals(output, 'hello moto', 'back 2');
  hub.redo();
  hub.redo();
  equals(output, 'once more', 'back to tip');
  hub.redo();
  return equals(output, 'once more', 'cannot go forward');
});
test('Undo/Redo', 12, function() {
  var Counter, counter, hub;
  hub = new PubSub;
  Counter = function() {
    this.count = 0;
    this.incr = __bind(function() {
      return this.count++;
    }, this);
    this.decr = __bind(function() {
      return this.count--;
    }, this);
    return this;
  };
  counter = new Counter;
  hub.subscribe('foo', counter.incr, counter.decr);
  hub.undo();
  equals(counter.count, 0, 'cannot go backward');
  hub.publish('foo');
  equals(counter.count, 1, '+1');
  hub.undo();
  equals(counter.count, 0, '-1');
  hub.undo();
  equals(counter.count, 0, 'still cannot go backward');
  hub.redo();
  equals(counter.count, 1, 'back to +1');
  hub.publish('foo');
  equals(counter.count, 2, '+1');
  hub.undo();
  equals(counter.count, 1, '-1');
  hub.redo();
  equals(counter.count, 2, '+1');
  hub.publish('foo');
  equals(counter.count, 3, '+1');
  hub.undo();
  hub.undo();
  equals(counter.count, 1, '-2');
  hub.redo();
  hub.redo();
  equals(counter.count, 3, 'back to tip');
  hub.redo();
  return equals(counter.count, 3, 'cannot go forward');
});
test('Partial Redo, New Pubs', 12, function() {
  var hub, output;
  hub = new PubSub;
  output = void 0;
  hub.subscribe('foo', function(msg) {
    return output = msg;
  });
  hub.undo();
  equals(output, void 0, 'cannot go backward');
  hub.publish('foo', 'hello moto');
  equals(output, 'hello moto', 'updated');
  hub.undo();
  equals(output, void 0, 'handler called with no arguments');
  hub.redo();
  equals(output, 'hello moto', 'stays the same');
  hub.publish('foo', 'and again');
  equals(output, 'and again', 'updated');
  hub.undo();
  equals(output, 'hello moto', 'back 1');
  hub.publish('foo', 'new path');
  equals(output, 'new path', 'updated');
  equals(hub.redos.length, 0, 'redos flushed');
  hub.redo();
  equals(output, 'new path', 'stays the same');
  hub.undo();
  hub.undo();
  equals(output, void 0, 'back 2');
  hub.redo();
  hub.redo();
  equals(output, 'new path', 'back to tip');
  hub.redo();
  return equals(output, 'new path', 'cannot go forward');
});
test('Non-Idempotent Partial Redo, New Pubs', 12, function() {
  var Counter, counter, hub;
  hub = new PubSub;
  Counter = function() {
    this.count = 0;
    this.incr = __bind(function() {
      return this.count++;
    }, this);
    this.decr = __bind(function() {
      return this.count--;
    }, this);
    return this;
  };
  counter = new Counter;
  hub.subscribe('foo', counter.incr, counter.decr);
  hub.undo();
  equals(counter.count, 0, 'cannot go backward');
  hub.publish('foo');
  equals(counter.count, 1, '+1');
  hub.undo();
  equals(counter.count, 0, '-1');
  hub.undo();
  equals(counter.count, 0, 'still cannot go backward');
  hub.redo();
  equals(counter.count, 1, 'back to +1');
  hub.publish('foo');
  equals(counter.count, 2, '+1');
  hub.undo();
  equals(counter.count, 1, '-1');
  hub.publish('foo');
  equals(hub.redos.length, 0, 'redos flushed');
  hub.publish('foo');
  equals(counter.count, 3, '+2');
  hub.redo();
  equals(counter.count, 3, 'stays the same');
  hub.undo();
  hub.undo();
  equals(counter.count, 1, '-2');
  hub.redo();
  hub.redo();
  return equals(counter.count, 3, 'back to tip');
});
test('Nested Publish Calls', function() {
  var Counter, c1, c2, hub, out;
  hub = new PubSub;
  Counter = function() {
    this.count = 0;
    this.incr = __bind(function() {
      return ++this.count;
    }, this);
    this.decr = __bind(function() {
      return --this.count;
    }, this);
    return this;
  };
  c1 = new Counter;
  c2 = new Counter;
  hub.subscribe('foo', function() {
    return hub.publish('bar', c1.incr());
  }, function() {
    return hub.publish('bar', c1.decr());
  });
  hub.subscribe('bar', function() {
    if (c2.count < 3) {
      return c2.incr();
    }
  }, function() {
    if (c2.count > 0) {
      return c2.decr();
    }
  });
  hub.publish('foo');
  equals(c1.count, 1);
  equals(c2.count, 1);
  hub.undo();
  equals(c1.count, 0);
  equals(c2.count, 0);
  hub.redo();
  equals(c1.count, 1);
  equals(c2.count, 1);
  hub.publish('foo');
  hub.publish('foo');
  hub.publish('foo');
  equals(c1.count, 4);
  equals(c2.count, 3);
  hub.undo();
  hub.undo();
  equals(c1.count, 2);
  equals(c2.count, 1);
  out = 0;
  hub.subscribe('bar', function(count) {
    return out = Math.pow(2, count);
  });
  equals(out, 0);
  hub.redo();
  equals(out, 8);
  hub.undo();
  return equals(out, 4);
});
