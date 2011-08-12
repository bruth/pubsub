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
    # subscriber can be deactivated at any time to prevent (or suspend) future
    # messages from being received. On re-activation, it can optionally receive
    # the queued up messages since it was last subscribed.
    class Subscriber
        constructor: (@publisher, @forwards, @backwards, @context) ->
            @id = suid++
            @online = true
            @tip = null
            @hub = @publisher.hub

    # Message
    # -------
    # A message is created and sent by it's ``publisher``. A message is
    # composed simply of arguments that will be passed into the subscriber's
    # handlers.
    class Message
        constructor: (@publisher, @content) ->
            @id = muid++
            @previous = @publisher.tip()
            @publisher.messages.push @ 
            @hub = @publisher.hub
            @hub.messages[@id] = @

        copy: -> @content.slice()

        available: -> @publisher.active

    # Publisher
    # ---------
    # Messages are send via a publisher whom broadcasts them to it's
    # subscribers. Similarly to a subscriber, a publisher can also
    # be deactivated. During this time, no messages will be queued nor
    # broadcasted to it's subscribers.
    class Publisher
        constructor: (@hub, @topic) ->
            @subscribers = []
            @messages = []
            @active = true

        _add: (subscriber) -> @subscribers.push subscriber

        # Dereferences a subscriber from the local list
        _remove: (subscriber) ->
            len = @subscribers.length
            while len--
                if subscriber is @subscribers[len]
                    @subscriber.pop len
                    break

        tip: -> @messages[@messages.length - 1]

        # Purges a message given it's id.
        purge: (message) ->
            len = @messages.length
            while len--
                if message is @messages[len]
                    @messages.pop len
                    break

    class PubSub
        version: '@VERSION'

        # The ``PubSub`` constructor takes a single optional argument
        # ``undoStackSize`` which specifies a limit to the undo stack size. If
        # it reaches the limit, the oldest undo will be shifted off
        constructor: (@undoStackSize) ->
            @publishers = {}
            @subscribers = {}
            @messages = {}
            @tip = null
            @undos = []
            @redos = []

        _addPublisher: (topic) ->
            if not (publisher = @publishers[topic])
                publisher = new Publisher @, topic
                @publishers[topic] = publisher
            return publisher

        _addSubscriber: (publisher, forwards, backwards, context) ->
            subscriber = new Subscriber publisher, forwards, backwards, context
            @subscribers[subscriber.id] = subscriber
            publisher._add subscriber
            return subscriber

        # Subscribes a handler for the given publisher. For [idempotent][1]
        # subscribers, only the ``forwards`` handler is required. For
        # non-idempotent subscribers a ``backwards`` handler must also be
        # defined to ensure consistency during undo/redo operations.
        #
        # An optional ``context`` can be supplied for the ``forwards`` and
        # ``backwards`` handlers. 
        #
        # When a new (or existing) subscriber is created, by default, any
        # messages that have already been queued up by the publisher is
        # forwarded to the subscriber. Migration can be turned off ``false`` to
        # prevent migrating.
        #
        # In addition to new subscribers, an existing subscriber can be
        # re-subscribed. If this method is used, the second parameter is
        # the ``migrate`` paramter.
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

        _migrate: (publisher, subscriber, type) ->
            # Ensure this new subscriber does not go past the hub's current
            # state and does not respond to a former message.
            if publisher.messages.length
                switch type
                    when true
                        messages = publisher.messages
                    when 'tip'
                        messages = [publisher.tip()]

                for message in messages
                    if message.id > @tip.id
                        break
                    if subscriber.tip and subscriber.tip.id >= message.id
                        continue
                    subscriber.forwards.apply subscriber.context, message.copy()

                subscriber.tip = message

            # return the subscriber id for later reference in the application
            return subscriber.id

        # Unsubscribe all subscribers for a given ``publisher`` is a publisher topic is
        # supplied or unsubscribe a subscriber via their ``id``. If ``remove``
        # is ``true``, all references to the unsubscribed object will be
        # deleted from this hub.
        unsubscribe: (subscriber, complete=false) ->
            if not subscriber instanceof Subscriber
                return if not (subscriber = @subscribers[subscriber])

            if complete
                delete @subscribers[subscriber.id]
                subscriber.publisher._remove subscriber
            else
                subscriber.online = false

        # The workhorse of the ``publish`` method. For a publisher ``topic``, all
        # subscribers will their ``forwards`` handler be executed with ``args``
        # being passed in.
        #
        # Currently, only top-level messages are recorded. If the hub's
        # ``locked`` flag is ``true``, no message is recorded.
        publish: (topic, args...) ->

            if not (publisher = @publishers[topic])
                publisher = @publishers[topic] = new Publisher @, topic
            else if not publisher.active
                return

            message = null

            # A message will only be recorded when it's a top-level call.
            # This ensures consistency for the undo/redo stacks
            if not @locked
                # Record this message to the hub
                message = @_record(publisher, args)

            # If there are any subscribers, execute their respective ``forwards``
            # handlers.
            if publisher.subscribers.length
                for subscriber in publisher.subscribers
                    # Skip temporarily unsubscribed subscribers
                    if not subscriber.online then continue
                    # Create copies of ``args`` to ensure no side-effects
                    # between subscribers.
                    @_transaction subscriber, message, args.slice(0)

            return message and message.id

        # Undo the last message for this hub. Recursively skip any pubs
        # which have an unsubscribed publisher.
        undo: ->
            if (message = @undos.pop())
                @redos.push message
                if message.available() then @_backwards message else @undo()

        # Redo the next message for this hub. Recursively skip any pubs
        # which have an unsubscribed publisher.
        redo: ->
            if (message = @redos.pop())
                @undos.push message
                if message.available() then @_forwards message else @redo()

        # Encapsulates a _new_ ``forwards`` execution. This hub is locked for
        # the during of this call stack (relative to the handler) to prevent
        # dependent messages from being recorded in the messages.
        #
        # Errors must be caught here to ensure other subscribers are not
        # affected downstream.
        _transaction: (subscriber, message, args) ->
            if not @locked
                @locked = true
                try
                    subscriber.forwards.apply subscriber.context, args
                    subscriber.tip = message
                finally
                    @locked = false
            else
                try subscriber.forwards.apply subscriber.context, args

        # The logic behind the ``redo`` operation. Each online subscriber for
        # the ``message``'s publisher is targeted.
        #
        # Errors must be caught here to ensure other subscribers are not
        # affected downstream.
        _forwards: (message) ->

            publisher = message.publisher
            if publisher.subscribers.length
                for subscriber in publisher.subscribers
                    if not subscriber.online then continue
                    try
                        subscriber.forwards.apply subscriber.context, message.copy()
                    finally
                        subscriber.tip = message

            @tip = message

        # The logic behind the ``undo`` operation. Each online subscriber for
        # the ``message``'s publisher is targeted. If the ``backwards`` handler is not
        # defined, the ``forwards`` handler will be used with the previous
        # message's ``content`` for the publisher to mimic the last state.
        #
        # Errors must be caught here to ensure other subscribers are not
        # affected downstream.
        _backwards: (message) ->

            publisher = message.publisher
            if publisher.subscribers.length
                for subscriber in publisher.subscribers
                    if not subscriber.online then continue

                    try
                        if not subscriber.backwards
                            if message.previous
                                subscriber.forwards.apply subscriber.context, message.previous.copy()
                            else
                                subscriber.forwards.apply subscriber.context
                        else
                            subscriber.backwards.apply subscriber.context, message.copy()
                    finally
                        subscriber.tip = message

            @tip = message

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
            message.publisher.purge message
            delete @messages[message.id]

        # Create a new ``message``, store a reference to the last message relative
        # to the publisher. This is for idempotent (or those without a
        # ``backwards`` handler) subscribers.
        _record: (publisher, args) ->
            @_flush()
            message = new Message publisher, args
            @_prune()
            @undos.push message
            @tip = message
            message

    window.PubSub = PubSub
