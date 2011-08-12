var __slice = Array.prototype.slice;
(function(window) {
  var Message, PubSub, Publisher, Subscriber, muid, suid;
  suid = 1;
  muid = 1;
  Subscriber = (function() {
    function Subscriber(publisher, forwards, backwards, context) {
      this.publisher = publisher;
      this.forwards = forwards;
      this.backwards = backwards;
      this.context = context;
      this.id = suid++;
      this.online = true;
      this.tip = null;
      this.hub = this.publisher.hub;
    }
    return Subscriber;
  })();
  Message = (function() {
    function Message(publisher, content) {
      this.publisher = publisher;
      this.content = content;
      this.id = muid++;
      this.previous = this.publisher.tip();
      this.publisher.messages.push(this);
      this.hub = this.publisher.hub;
      this.hub.messages[this.id] = this;
    }
    Message.prototype.copy = function() {
      return this.content.slice();
    };
    Message.prototype.available = function() {
      return this.publisher.active;
    };
    return Message;
  })();
  Publisher = (function() {
    function Publisher(hub, topic) {
      this.hub = hub;
      this.topic = topic;
      this.subscribers = [];
      this.messages = [];
      this.active = true;
    }
    Publisher.prototype._add = function(subscriber) {
      return this.subscribers.push(subscriber);
    };
    Publisher.prototype._remove = function(subscriber) {
      var len, _results;
      len = this.subscribers.length;
      _results = [];
      while (len--) {
        if (subscriber === this.subscribers[len]) {
          this.subscriber.pop(len);
          break;
        }
      }
      return _results;
    };
    Publisher.prototype.tip = function() {
      return this.messages[this.messages.length - 1];
    };
    Publisher.prototype.purge = function(message) {
      var len, _results;
      len = this.messages.length;
      _results = [];
      while (len--) {
        if (message === this.messages[len]) {
          this.messages.pop(len);
          break;
        }
      }
      return _results;
    };
    return Publisher;
  })();
  PubSub = (function() {
    PubSub.prototype.version = '0.2.1';
    function PubSub(undoStackSize) {
      this.undoStackSize = undoStackSize;
      this.publishers = {};
      this.subscribers = {};
      this.messages = {};
      this.tip = null;
      this.undos = [];
      this.redos = [];
    }
    PubSub.prototype._addPublisher = function(topic) {
      var publisher;
      if (!(publisher = this.publishers[topic])) {
        publisher = new Publisher(this, topic);
        this.publishers[topic] = publisher;
      }
      return publisher;
    };
    PubSub.prototype._addSubscriber = function(publisher, forwards, backwards, context) {
      var subscriber;
      subscriber = new Subscriber(publisher, forwards, backwards, context);
      this.subscribers[subscriber.id] = subscriber;
      publisher._add(subscriber);
      return subscriber;
    };
    PubSub.prototype.subscribe = function(topic, forwards, backwards, context, migrate) {
      var publisher, subscriber;
      if (migrate == null) {
        migrate = true;
      }
      if (topic instanceof Subscriber) {
        subscriber = topic;
        subscriber.online = true;
        publisher = subscriber.publisher;
        migrate = forwards || migrate;
      } else {
        publisher = this._addPublisher(topic);
        subscriber = this._addSubscriber(publisher, forwards, backwards, context);
      }
      if (migrate) {
        this._migrate(publisher, subscriber, migrate);
      }
      return subscriber;
    };
    PubSub.prototype._migrate = function(publisher, subscriber, type) {
      var message, messages, _i, _len;
      if (publisher.messages.length) {
        switch (type) {
          case true:
            messages = publisher.messages;
            break;
          case 'tip':
            messages = [publisher.tip()];
        }
        for (_i = 0, _len = messages.length; _i < _len; _i++) {
          message = messages[_i];
          if (message.id > this.tip.id) {
            break;
          }
          if (subscriber.tip && subscriber.tip.id >= message.id) {
            continue;
          }
          subscriber.forwards.apply(subscriber.context, message.copy());
        }
        subscriber.tip = message;
      }
      return subscriber.id;
    };
    PubSub.prototype.unsubscribe = function(subscriber, complete) {
      if (complete == null) {
        complete = false;
      }
      if (!subscriber instanceof Subscriber) {
        if (!(subscriber = this.subscribers[subscriber])) {
          return;
        }
      }
      if (complete) {
        delete this.subscribers[subscriber.id];
        return subscriber.publisher._remove(subscriber);
      } else {
        return subscriber.online = false;
      }
    };
    PubSub.prototype.publish = function() {
      var args, message, publisher, subscriber, topic, _i, _len, _ref;
      topic = arguments[0], args = 2 <= arguments.length ? __slice.call(arguments, 1) : [];
      if (!(publisher = this.publishers[topic])) {
        publisher = this.publishers[topic] = new Publisher(this, topic);
      } else if (!publisher.active) {
        return;
      }
      message = null;
      if (!this.locked) {
        message = this._record(publisher, args);
      }
      if (publisher.subscribers.length) {
        _ref = publisher.subscribers;
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          subscriber = _ref[_i];
          if (!subscriber.online) {
            continue;
          }
          this._transaction(subscriber, message, args.slice(0));
        }
      }
      return message && message.id;
    };
    PubSub.prototype.undo = function() {
      var message;
      if ((message = this.undos.pop())) {
        this.redos.push(message);
        if (message.available()) {
          return this._backwards(message);
        } else {
          return this.undo();
        }
      }
    };
    PubSub.prototype.redo = function() {
      var message;
      if ((message = this.redos.pop())) {
        this.undos.push(message);
        if (message.available()) {
          return this._forwards(message);
        } else {
          return this.redo();
        }
      }
    };
    PubSub.prototype._transaction = function(subscriber, message, args) {
      if (!this.locked) {
        this.locked = true;
        try {
          subscriber.forwards.apply(subscriber.context, args);
          return subscriber.tip = message;
        } finally {
          this.locked = false;
        }
      } else {
        try {
          return subscriber.forwards.apply(subscriber.context, args);
        } catch (_e) {}
      }
    };
    PubSub.prototype._forwards = function(message) {
      var publisher, subscriber, _i, _len, _ref;
      publisher = message.publisher;
      if (publisher.subscribers.length) {
        _ref = publisher.subscribers;
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          subscriber = _ref[_i];
          if (!subscriber.online) {
            continue;
          }
          try {
            subscriber.forwards.apply(subscriber.context, message.copy());
          } finally {
            subscriber.tip = message;
          }
        }
      }
      return this.tip = message;
    };
    PubSub.prototype._backwards = function(message) {
      var publisher, subscriber, _i, _len, _ref;
      publisher = message.publisher;
      if (publisher.subscribers.length) {
        _ref = publisher.subscribers;
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          subscriber = _ref[_i];
          if (!subscriber.online) {
            continue;
          }
          try {
            if (!subscriber.backwards) {
              if (message.previous) {
                subscriber.forwards.apply(subscriber.context, message.previous.copy());
              } else {
                subscriber.forwards.apply(subscriber.context);
              }
            } else {
              subscriber.backwards.apply(subscriber.context, message.copy());
            }
          } finally {
            subscriber.tip = message;
          }
        }
      }
      return this.tip = message;
    };
    PubSub.prototype._flush = function() {
      var len, message, _results;
      len = this.redos.length;
      _results = [];
      while (len--) {
        message = this.redos.shift();
        _results.push(this._purge(message));
      }
      return _results;
    };
    PubSub.prototype._prune = function() {
      var message;
      if (this.undoStackSize && this.undos.length === this.undoStackSize) {
        message = this.undos.shift();
        return this._purge(message);
      }
    };
    PubSub.prototype._purge = function(message) {
      message.publisher.purge(message);
      return delete this.messages[message.id];
    };
    PubSub.prototype._record = function(publisher, args) {
      var message;
      this._flush();
      message = new Message(publisher, args);
      this._prune();
      this.undos.push(message);
      this.tip = message;
      return message;
    };
    return PubSub;
  })();
  return window.PubSub = PubSub;
})(window);
