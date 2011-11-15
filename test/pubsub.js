var __slice = Array.prototype.slice;
define(function() {
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
    function Message(publisher, content, temp) {
      this.publisher = publisher;
      this.content = content;
      this.temp = temp != null ? temp : false;
      if (!this.temp) {
        this.id = muid++;
        this.previous = this.publisher.tip();
        this.publisher.messages.push(this);
      }
    }
    Message.prototype.copy = function() {
      if (this.content) {
        return this.content.slice();
      } else {
        return [];
      }
    };
    Message.prototype.available = function() {
      return this.publisher.active;
    };
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
    Publisher.prototype._purge = function(message) {
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
    PubSub.prototype.version = '0.3-undo';
    function PubSub(undoStackSize) {
      this.undoStackSize = undoStackSize;
      this.publishers = {};
      this.subscribers = {};
      this.messages = {};
      this.undos = [];
      this.redos = [];
    }
    PubSub.prototype._addPublisher = function(topic) {
      var publisher;
      if (!(publisher = this.publishers[topic])) {
        publisher = new Publisher(topic);
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
    PubSub.prototype.tip = function() {
      return this.undos[this.undos.length - 1];
    };
    PubSub.prototype.subscribe = function(topic, forwards, backwards, context, migrate) {
      var publisher, subscriber, _ref;
      if (migrate == null) {
        migrate = true;
      }
      if (topic instanceof Subscriber) {
        subscriber = topic;
        subscriber.online = true;
        publisher = subscriber.publisher;
        migrate = forwards || migrate;
      } else {
        if (backwards === true || backwards === 'tip' || backwards === false) {
          _ref = [backwards, migrate], migrate = _ref[0], backwards = _ref[1];
        }
        publisher = this._addPublisher(topic);
        subscriber = this._addSubscriber(publisher, forwards, backwards, context);
      }
      if (migrate) {
        this._migrate(publisher, subscriber, migrate);
      }
      return subscriber;
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
      var content, message, publisher, topic, _init;
      topic = arguments[0], content = 2 <= arguments.length ? __slice.call(arguments, 1) : [];
      publisher = this._addPublisher(topic);
      if (!publisher.active) {
        return;
      }
      _init = this.locked ? this._temp : this._record;
      message = _init.call(this, publisher, content);
      if (!this.direction || this.direction === 'forward') {
        this._forwardAll(message);
      } else {
        this._backwardAll(message);
      }
      return publisher;
    };
    PubSub.prototype.undo = function() {
      var message;
      if ((message = this.undos.pop())) {
        this.redos.push(message);
        if (message.available()) {
          return this._backwardAll(message);
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
          return this._forwardAll(message);
        } else {
          return this.redo();
        }
      }
    };
    PubSub.prototype._migrate = function(publisher, subscriber, type) {
      var htip, messages, stip;
      if (publisher.messages.length) {
        htip = this.tip().id;
        stip = (stip = subscriber.tip) ? stip.id : -1;
        if (htip === stip) {
          return;
        }
        messages = publisher.messages;
        if (htip > stip) {
          if (type === 'tip') {
            messages = [publisher.tip()];
          }
          return this._migrateForward(messages, subscriber, stip);
        } else {
          return this._migrateBackward(messages, subscriber, stip);
        }
      }
    };
    PubSub.prototype._migrateForward = function(messages, subscriber, tip) {
      var message, _i, _len, _results;
      _results = [];
      for (_i = 0, _len = messages.length; _i < _len; _i++) {
        message = messages[_i];
        if (message.id <= tip) {
          continue;
        }
        _results.push(this._forwardOne(message, subscriber));
      }
      return _results;
    };
    PubSub.prototype._migrateBackward = function(messages, subscriber, tip) {
      var len, message, _results;
      len = messages.length;
      _results = [];
      while (len--) {
        message = messages[len];
        if (tip <= message.id) {
          continue;
        }
        _results.push(this._backwardOne(message, subscriber));
      }
      return _results;
    };
    PubSub.prototype._forwardAll = function(message, tip) {
      var subscriber, _i, _len, _ref;
      _ref = message.publisher.subscribers;
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        subscriber = _ref[_i];
        this._forwardOne(message, subscriber, tip);
      }
    };
    PubSub.prototype._forwardOne = function(message, subscriber) {
      if (!subscriber.online) {
        return;
      }
      if (!this.locked) {
        this.locked = true;
        this.direction = 'forward';
        try {
          this.__forward(message, subscriber);
          subscriber.tip = message;
        } finally {
          this.locked = false;
          this.direction = null;
        }
      } else {
        this.__forward(message, subscriber);
      }
    };
    PubSub.prototype.__forward = function(message, subscriber) {
      return subscriber.forwards.apply(subscriber.context, message.copy());
    };
    PubSub.prototype._backwardAll = function(message, tip) {
      var len, subscribers;
      subscribers = message.publisher.subscribers;
      len = subscribers.length;
      while (len--) {
        this._backwardOne(message, subscribers[len], tip);
      }
    };
    PubSub.prototype._backwardOne = function(message, subscriber) {
      if (!subscriber.online) {
        return;
      }
      if (!this.locked) {
        this.locked = true;
        this.direction = 'backward';
        try {
          this.__backward(subscriber, message);
          subscriber.tip = message;
        } finally {
          this.locked = false;
          this.direction = null;
        }
      } else {
        this.__backward(subscriber, message);
      }
    };
    PubSub.prototype.__backward = function(subscriber, message) {
      var copy;
      if (subscriber.backwards) {
        return subscriber.backwards.apply(subscriber.context, message.copy());
      } else {
        if (message.temp) {
          copy = message.copy();
        } else if (message.previous) {
          copy = message.previous.copy();
        } else {
          copy = [];
        }
        return subscriber.forwards.apply(subscriber.context, copy);
      }
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
      message.publisher._purge(message);
      return delete this.messages[message.id];
    };
    PubSub.prototype._record = function(publisher, content) {
      var message;
      this._flush();
      message = new Message(publisher, content);
      this.messages[message.id] = this;
      this._prune();
      this.undos.push(message);
      return message;
    };
    PubSub.prototype._temp = function(publisher, content) {
      return new Message(publisher, content, true);
    };
    return PubSub;
  })();
  return PubSub;
});
