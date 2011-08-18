var __slice = Array.prototype.slice;
(function(window) {
  var Message, PubSub, Publisher, Subscriber, muid, suid;
  suid = 1;
  muid = 1;
  Subscriber = (function() {
    function Subscriber(publisher, handler, context) {
      this.publisher = publisher;
      this.handler = handler;
      this.context = context;
      this.id = suid++;
      this.online = true;
      this.tip = null;
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
    return Publisher;
  })();
  PubSub = (function() {
    PubSub.prototype.version = '0.3';
    function PubSub() {
      this.publishers = {};
      this.subscribers = {};
      this.messages = {};
    }
    PubSub.prototype._addPublisher = function(topic) {
      var publisher;
      if (!(publisher = this.publishers[topic])) {
        publisher = new Publisher(topic);
        this.publishers[topic] = publisher;
      }
      return publisher;
    };
    PubSub.prototype._addSubscriber = function(publisher, handler, context) {
      var subscriber;
      subscriber = new Subscriber(publisher, handler, context);
      this.subscribers[subscriber.id] = subscriber;
      publisher._add(subscriber);
      return subscriber;
    };
    PubSub.prototype.subscribe = function(topic, handler, context, migrate) {
      var publisher, subscriber, _ref;
      if (migrate == null) {
        migrate = true;
      }
      if (topic instanceof Subscriber) {
        subscriber = topic;
        subscriber.online = true;
        publisher = subscriber.publisher;
        migrate = handler || migrate;
      } else {
        if (context === true || context === 'tip' || context === false) {
          _ref = [context, migrate], migrate = _ref[0], context = _ref[1];
        }
        publisher = this._addPublisher(topic);
        subscriber = this._addSubscriber(publisher, handler, context);
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
      var content, message, publisher, topic;
      topic = arguments[0], content = 2 <= arguments.length ? __slice.call(arguments, 1) : [];
      publisher = this._addPublisher(topic);
      if (!publisher.active) {
        return;
      }
      message = this._record(publisher, content);
      this._applyToAll(message);
      return publisher;
    };
    PubSub.prototype._migrate = function(publisher, subscriber, type) {
      var messages, tip;
      if (publisher.messages.length) {
        if (type === 'tip') {
          messages = [publisher.tip()];
        } else {
          messages = publisher.messages;
        }
        tip = subscriber.tip ? subscriber.tip.id : -1;
        return this._migrateAll(messages, subscriber, tip);
      }
    };
    PubSub.prototype._migrateAll = function(messages, subscriber, tip) {
      var message, _i, _len, _results;
      _results = [];
      for (_i = 0, _len = messages.length; _i < _len; _i++) {
        message = messages[_i];
        if (message.id <= tip) {
          continue;
        }
        _results.push(this._applyToOne(message, subscriber));
      }
      return _results;
    };
    PubSub.prototype._applyToAll = function(message, tip) {
      var subscriber, _i, _len, _ref;
      _ref = message.publisher.subscribers;
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        subscriber = _ref[_i];
        this._applyToOne(message, subscriber, tip);
      }
    };
    PubSub.prototype._applyToOne = function(message, subscriber) {
      if (!subscriber.online) {
        return;
      }
      subscriber.handler.apply(subscriber.context, message.copy());
      return subscriber.tip = message;
    };
    PubSub.prototype._record = function(publisher, content) {
      var message;
      message = new Message(publisher, content);
      this.messages[message.id] = this;
      return message;
    };
    return PubSub;
  })();
  return window.PubSub = PubSub;
})(window);
