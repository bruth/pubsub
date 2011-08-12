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

    # Message
    # -------
    # A message is created and sent by it's ``publisher``. A message is
    # composed simply of arguments that will be passed into the subscriber's
    # handlers.
    class Message
        constructor: (@publisher, @content) ->
            @id = muid++
            @previous = @publisher.tip()

        copy: -> @content.slice()

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

            if typeof topic is 'number'
                if not (subscriber = @subscribers[topic]) then return
                subscriber.online = true
                publisher = subscriber.publisher
                publish = forwards or publish
            else
                if not (publisher = @publishers[topic])
                    publisher = @publishers[topic] = new Publisher topic

                else if not forwards or typeof forwards isnt 'function'
                    publisher.active = true
                    return

                subscriber = new Subscriber publisher, forwards, backwards, context

                @subscribers[subscriber.id] = subscriber
                publisher.subscribers.push subscriber

            if migrate then @_migrate publisher, subscriber, migrate

            return subscriber.id

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
        unsubscribe: (topic, hard=false) ->

            if typeof topic is 'number'
                subscriber = @subscribers[topic]
                if hard
                    delete @subscribers[topic]
                    subscribers = subscriber.publisher.subscribers
                    len = subscribers.length
                    while len--
                        if subscriber.id is subscribers[len].id
                            subscribers.splice len, 1
                else
                    subscriber.online = false

            # Handles unsubscribing a whole publisher, i.e. it will no longer
            # broadcast or record new messages.
            else
                if (publisher = @publishers[topic])
                    if hard 
                        for subscriber in @publishers[topic].subscribers
                            delete @subscribers[subscriber.id]
                        delete @publishers[topic]
                    else
                        publisher.active = false

        # The workhorse of the ``publish`` method. For a publisher ``topic``, all
        # subscribers will their ``forwards`` handler be executed with ``args``
        # being passed in.
        #
        # Currently, only top-level messages are recorded. If the hub's
        # ``locked`` flag is ``true``, no message is recorded.
        publish: (topic, args...) ->

            if not (publisher = @publishers[topic])
                publisher = @publishers[topic] = new Publisher topic
            else if not publisher.active
                return

            message = null

            # A message will only be recorded when it's a top-level call.
            # This ensures consistency for the undo/redo stacks
            if not @locked 
                # Flush the redo before adding a new message to prevent invalid
                # references.
                @_flush()
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
                if not message.publisher.active
                    @undo()
                else
                    @_backwards message

        # Redo the next message for this hub. Recursively skip any pubs
        # which have an unsubscribed publisher.
        redo: ->

            if (message = @redos.pop())
                @undos.push message
                if not message.publisher.active
                    @redo()
                else
                    @_forwards message

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
            for _ in @redos
                message = @redos.shift()
                message.publisher.messages.pop()
                delete @messages[message.id]

        # Create a new ``message``, store a reference to the last message relative
        # to the publisher. This is for idempotent (or those without a
        # ``backwards`` handler) subscribers.
        # 
        # This ``message`` is added to the publisher messages, the undo stack and
        # is set as the hub's ``tip`` message.
        #
        # If ``undoStackSize`` has been defined, the oldest undo will be shifted off the
        # front of the stack.
        _record: (publisher, args) ->
            message = new Message publisher, args
            @messages[message.id] = message
            publisher.messages.push message

            if @undoStackSize and @undos.length is @undoStackSize
                @undos.shift()
            @undos.push message

            @tip = message


    window.PubSub = PubSub
