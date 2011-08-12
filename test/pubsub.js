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
    }
    return Subscriber;
  })();
  Message = (function() {
    function Message(publisher, args, previous) {
      this.publisher = publisher;
      this.args = args;
      this.previous = previous;
      this.id = muid++;
    }
    return Message;
  })();
  Publisher = (function() {
    function Publisher(topic) {
      this.topic = topic;
      this.subscribers = [];
      this.messages = [];
      this.active = true;
    }
    Publisher.prototype.tip = function() {
      return this.messages[this.messages.length - 1];
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
    PubSub.prototype.subscribe = function(topic, forwards, backwards, context, history) {
      var message, messages, publish, publisher, subscriber, _i, _len;
      if (history == null) {
        history = 'full';
      }
      if (typeof topic === 'number') {
        if (!(subscriber = this.subscribers[topic])) {
          return;
        }
        subscriber.online = true;
        publisher = subscriber.publisher;
        publish = forwards || publish;
      } else {
        if (!(publisher = this.publishers[topic])) {
          publisher = this.publishers[topic] = new Publisher(topic);
        } else if (!forwards || typeof forwards !== 'function') {
          publisher.active = true;
          return;
        }
        subscriber = new Subscriber(publisher, forwards, backwards, context);
        this.subscribers[subscriber.id] = subscriber;
        publisher.subscribers.push(subscriber);
      }
      if (publisher.messages.length) {
        switch (history) {
          case 'full':
            messages = publisher.messages;
            break;
          case 'tip':
            messages = [publisher.tip()];
            break;
          default:
            messages = [];
        }
        for (_i = 0, _len = messages.length; _i < _len; _i++) {
          message = messages[_i];
          if (message.id > this.tip.id) {
            break;
          }
          if (subscriber.tip && subscriber.tip.id >= message.id) {
            continue;
          }
          subscriber.forwards.apply(subscriber.context, message.args);
        }
        subscriber.tip = message;
      }
      return subscriber.id;
    };
    PubSub.prototype.unsubscribe = function(topic, hard) {
      var len, publisher, subscriber, subscribers, _i, _len, _ref, _results;
      if (hard == null) {
        hard = false;
      }
      if (typeof topic === 'number') {
        subscriber = this.subscribers[topic];
        if (hard) {
          delete this.subscribers[topic];
          subscribers = subscriber.publisher.subscribers;
          len = subscribers.length;
          _results = [];
          while (len--) {
            _results.push(subscriber.id === subscribers[len].id ? subscribers.splice(len, 1) : void 0);
          }
          return _results;
        } else {
          return subscriber.online = false;
        }
      } else {
        if ((publisher = this.publishers[topic])) {
          if (hard) {
            _ref = this.publishers[topic].subscribers;
            for (_i = 0, _len = _ref.length; _i < _len; _i++) {
              subscriber = _ref[_i];
              delete this.subscribers[subscriber.id];
            }
            return delete this.publishers[topic];
          } else {
            return publisher.active = false;
          }
        }
      }
    };
    PubSub.prototype.publish = function() {
      var args, message, publisher, subscriber, topic, _i, _len, _ref;
      topic = arguments[0], args = 2 <= arguments.length ? __slice.call(arguments, 1) : [];
      if (!(publisher = this.publishers[topic])) {
        publisher = this.publishers[topic] = new Publisher(topic);
      } else if (!publisher.active) {
        return;
      }
      message = null;
      if (!this.locked) {
        this._flush();
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
        if (!message.publisher.active) {
          return this.undo();
        } else {
          return this._backwards(message);
        }
      }
    };
    PubSub.prototype.redo = function() {
      var message;
      if ((message = this.redos.pop())) {
        this.undos.push(message);
        if (!message.publisher.active) {
          return this.redo();
        } else {
          return this._forwards(message);
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
            subscriber.forwards.apply(subscriber.context, message.args.slice(0));
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
                subscriber.forwards.apply(subscriber.context, message.previous.args.slice(0));
              } else {
                subscriber.forwards.apply(subscriber.context);
              }
            } else {
              subscriber.backwards.apply(subscriber.context, message.args.slice(0));
            }
          } finally {
            subscriber.tip = message;
          }
        }
      }
      return this.tip = message;
    };
    PubSub.prototype._flush = function() {
      var message, _, _i, _len, _ref, _results;
      _ref = this.redos;
      _results = [];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        _ = _ref[_i];
        message = this.redos.shift();
        message.publisher.messages.pop();
        _results.push(delete this.messages[message.id]);
      }
      return _results;
    };
    PubSub.prototype._record = function(publisher, args) {
      var message;
      message = new Message(publisher, args, publisher.tip());
      this.messages[message.id] = message;
      publisher.messages.push(message);
      if (this.undoStackSize && this.undos.length === this.undoStackSize) {
        this.undos.shift();
      }
      this.undos.push(message);
      return this.tip = message;
    };
    return PubSub;
  })();
  return window.PubSub = PubSub;
})(window);
