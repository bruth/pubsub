#
#     PubSub - The PubSub library with a history API
#     (c) 2011 Byron Ruth
#     PubSub may be freely distributed under the MIT license
#     Version: @VERSION
#

do (window) ->

    # Internal unique identifiers for messages and subscribers global to the
    # PubSub constructor. This ensures cross hub references never clash.
    suid = 1
    muid = 1

    # Subscriber
    # ----------
    # A subscriber is composed of a ``forwards`` handler and optionally a
    # ``backwards`` handler for supporting the PubSub history API. An optional
    # ``context`` can also be supplied to be the context for the handlers.
    #
    # ``tip`` represents the last message this subscriber has received. A
    # subscriber can be deactivated at any time by setting ``online`` to
    # ``false``. This prevents future messages from being received. If the
    # subscriber comes back _online_, it can optionally receive the queued
    # up messages since it was last subscribed.
    class Subscriber
        constructor: (@publisher, @forwards, @backwards, @context) ->
            @id = suid++
            @online = true
            @tip = null

    # Message
    # -------
    # A message is created and sent by it's ``publisher``. It is composed
    # simply of the arguments passed in on a ``publish`` call. The content
    # will be passed to the subscriber's handlers.
    class Message
        constructor: (@publisher, @content, @temp=false) ->
            if not @temp
                @id = muid++
                @previous = @publisher.tip()
                @publisher.messages.push @

        copy: -> if @content then @content.slice() else []

        available: -> @publisher.active

    # Publisher
    # ---------
    # Messages are send via a publisher whom broadcasts them to it's
    # subscribers. Similarly to a subscriber, a publisher can also
    # be deactivated. During this time, no messages will be queued nor
    # broadcasted to it's subscribers.
    class Publisher
        constructor: (@topic) ->
            @subscribers = []
            @messages = []
            @active = true

        tip: -> @messages[@messages.length - 1]

        _add: (subscriber) -> @subscribers.push subscriber

        # Dereferences a subscriber from the local list
        _remove: (subscriber) ->
            len = @subscribers.length
            while len--
                if subscriber is @subscribers[len]
                    @subscriber.pop len
                    break

        # Purges a message from this publisher's queue.
        _purge: (message) ->
            len = @messages.length
            while len--
                if message is @messages[len]
                    @messages.pop len
                    break

    # The ``PubSub`` constructor takes a single optional argument
    # ``undoStackSize`` which specifies a limit to the undo stack size. If
    # it reaches the limit, the oldest undo will be shifted off the bottom
    # of the stack.
    class PubSub
        version: '@VERSION'

        constructor: (@undoStackSize) ->
            @publishers = {}
            @subscribers = {}
            @messages = {}
            @undos = []
            @redos = []

        _addPublisher: (topic) ->
            if not (publisher = @publishers[topic])
                publisher = new Publisher topic
                @publishers[topic] = publisher
            return publisher

        _addSubscriber: (publisher, forwards, backwards, context) ->
            subscriber = new Subscriber publisher, forwards, backwards, context
            @subscribers[subscriber.id] = subscriber
            publisher._add subscriber
            return subscriber

        tip: -> @undos[@undos.length - 1]

        # Subscribes a handler for the given publisher. For [idempotent][1]
        # subscribers, only the ``forwards`` handler is required. For
        # non-idempotent subscribers a ``backwards`` handler must also be
        # defined to ensure consistency during undo/redo operations.
        #
        # An optional ``context`` can be supplied for the ``forwards`` and
        # ``backwards`` handlers. 
        #
        # When a new (or existing) subscriber is created, by default, any
        # messages that have already been queued up by the publisher are
        # forwarded to the subscriber. This _migration_ can be turned off
        # ``false`` to prevent this behavior.
        #
        # In addition to new subscribers, an existing subscriber can be
        # re-subscribed. If this method is used, the second parameter is
        # treated as the ``migrate`` paramter.
        #
        # [1]: http://en.wikipedia.org/wiki/Idempotence
        subscribe: (topic, forwards, backwards, context, migrate=true) ->
            if topic instanceof Subscriber
                subscriber = topic
                subscriber.online = true
                publisher = subscriber.publisher
                migrate = forwards or migrate 
            else
                publisher = @_addPublisher topic
                subscriber = @_addSubscriber publisher, forwards, backwards, context

            if migrate then @_migrate publisher, subscriber, migrate

            return subscriber

        # Unsubscribes a subscriber. If ``complete`` is ``true``, the
        # subscriber will be completed dereferenced from the hub.
        unsubscribe: (subscriber, complete=false) ->
            if not subscriber instanceof Subscriber
                return if not (subscriber = @subscribers[subscriber])

            if complete
                delete @subscribers[subscriber.id]
                subscriber.publisher._remove subscriber
            else
                subscriber.online = false

        # Publishes content for the specified ``topic``. 
        #
        # To support undo/redo operations only top-level calls to publish are
        # recorded. For each subscriber handler, the hub becomes locked for the
        # remainder of the _handling_. Once it finishes, the hub is unlocked
        # for the next subscriber handler to be executed.
        publish: (topic, content...) ->
            publisher = @_addPublisher topic
            return if not publisher.active

            _init = if @locked then @_temp else @_record
            message = _init.call @, publisher, content
            if not @direction or @direction is 'forward'
                @_forwardAll message
            else
                @_backwardAll message

            return publisher

        # Undo the last message for this hub. Recursively skip any messages
        # whos publisher is inactive.
        undo: ->
            if (message = @undos.pop())
                @redos.push message
                if message.available() then @_backwardAll message else @undo()

        # Redo the last message for this hub. Recursively skip any messages
        # whos publisher is inactive.
        redo: ->
            if (message = @redos.pop())
                @undos.push message
                if message.available() then @_forwardAll message else @redo()

        # Handles applying a migration for a subscriber depending on it's state
        # relative to the publisher and hub.
        _migrate: (publisher, subscriber, type) ->
            if publisher.messages.length
                # Determine whether the subscriber is ahead or behind in state
                # relative to the hub.
                htip = @tip().id
                stip = if (stip = subscriber.tip) then stip.id else -1

                return if htip is stip

                messages = publisher.messages

                # Must migrate forward
                if htip > stip
                    if type is 'tip'
                        messages = [publisher.tip()]
                    @_migrateForward messages, subscriber, stip
                else
                    @_migrateBackward messages, subscriber, stip


        # Applies a forward migration in the ascending order.
        _migrateForward: (messages, subscriber, tip) ->
            for message in messages
                continue if message.id <= tip
                @_forwardOne message, subscriber

        # Applies a backward migration in the descending order.
        _migrateBackward: (messages, subscriber, tip) ->
            len = messages.length
            while len--
                message = messages[len]
                continue if tip <= message.id
                @_backwardOne message, subscriber


        # Broadcasts a mesage to all subscribers of the messages' publisher.
        _forwardAll: (message, tip) ->
            for subscriber in message.publisher.subscribers
                @_forwardOne message, subscriber, tip
            return

        # Given a message and subscriber, forward the message to the subscriber
        # only if the subscriber is online and does not exceed the ``tip``
        # message. What ``tip`` denotes varies on the context of the
        # forwarding.
        #
        # This hub is locked for the during of this call stack (relative to
        # the handler) to prevent dependent messages from being recorded in
        # the messages.
        #
        # Errors must be caught here to ensure other subscribers are not
        # affected downstream.
        _forwardOne: (message, subscriber) ->
            return if not subscriber.online
            if not @locked
                @locked = true
                @direction = 'forward'
                try
                    @__forward message, subscriber
                    subscriber.tip = message
                finally
                    @locked = false
                    @direction = null
            else
                @__forward message, subscriber
            return

         __forward: (message, subscriber) ->
            subscriber.forwards.apply subscriber.context, message.copy()

        # Broadcasts a message to all subscribers of the messages' publisher.
        _backwardAll: (message, tip) ->
            subscribers = message.publisher.subscribers
            len = subscribers.length
            while len--
                @_backwardOne message, subscribers[len], tip
            return

        # Given a message and subscriber, backward the message from the subscriber
        # only if the subscriber is online and does not preceed the ``tip``
        # message. What ``tip`` denotes varies on the context of the
        # backwarding.
        #
        # This hub is locked for the during of this call stack (relative to
        # the handler) to prevent dependent messages from being recorded in
        # the messages.
        #
        # Errors must be caught here to ensure other subscribers are not
        # affected downstream.
        _backwardOne: (message, subscriber) ->
            return if not subscriber.online
            if not @locked
                @locked = true
                @direction = 'backward'
                try
                    @__backward subscriber, message
                    subscriber.tip = message
                finally
                    @locked = false
                    @direction = null
            else
                @__backward subscriber, message
            return

        # If a ``backwards`` handler exists for this subscriber, use the
        # message that has been passed in as is. Otherwise fallback to
        # the ``forwards`` handler. If the message passed in is not
        # temporary (i.e. has been recorded), use the previous message (to
        # mimic the previous state), otherwise use the message passed in.
        __backward: (subscriber, message) ->
            if subscriber.backwards
                subscriber.backwards.apply subscriber.context, message.copy()
            else
                if message.temp
                    copy = message.copy()
                else if message.previous
                    copy = message.previous.copy()
                else
                    copy = []
                subscriber.forwards.apply subscriber.context, copy

        # Takes each message in the ``redos`` and removes and  deferences them
        # from the respective ``publisher`` and the hub.
        _flush: ->
            len = @redos.length
            while len--
                message = @redos.shift()
                @_purge message

        # If ``undoStackSize`` has been defined, the oldest undo will be
        # shifted off from the front of the stack.
        _prune: ->
            if @undoStackSize and @undos.length is @undoStackSize
                message = @undos.shift()
                @_purge message

        # Purges messages that are no longer valid in the hub's current state. 
        # This includes _flushed_ messages from the ``redos`` stack as well as
        # ``undos`` that have been shifted off the beginning of the stack.
        _purge: (message) ->
            message.publisher._purge message
            delete @messages[message.id]

        # Create a new ``message``, store a reference to the last message relative
        # to the publisher. This is for idempotent (or those without a
        # ``backwards`` handler) subscribers.
        _record: (publisher, content) ->
            @_flush()
            message = new Message publisher, content
            @messages[message.id] = @
            @_prune()
            @undos.push message
            return message

        _temp: (publisher, content) ->
            new Message publisher, content, true

    window.PubSub = PubSub
