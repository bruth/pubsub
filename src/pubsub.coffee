#
#     PubSub - The PubSub library with a history API
#     (c) 2011 Byron Ruth
#     PubSub may be freely distributed under the MIT license
#     Version: @VERSION
#

do (window) ->

    # Add helper function to Array
    if not Array::last then Array::last = -> @[@length - 1]

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
            @active = true
            @tip = null

    # Message
    # -------
    # A message is created and sent by it's ``publisher``. A message is
    # composed simply of arguments that will be passed into the subscriber's
    # handlers.
    class Message
        constructor: (@publisher, @args, @previous) ->
            @id = muid++

    # Publisher
    # ---------
    # Messages are send via a publisher whom broadcasts them to it's
    # subscribers. Similarly to a subscriber, a publisher can also
    # be deactivated. During this time, no messages will be queued nor
    # broadcasted to it's subscribers.
    class Publisher
        constructor: (@name) ->
            @subscribers = []
            @messages = []
            @active = true

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
            @_undos = []
            @_redos = []

        # Subscribes a handler for the given publisher. For [idempotent][1]
        # subscribers, only the ``forwards`` handler is required. For
        # non-idempotent subscribers a ``backwards`` handler must also be
        # defined to ensure consistency during undo/redo operations.
        #
        # An optional ``context`` can be supplied for the ``forwards`` and
        # ``backwards`` handlers. 
        #
        # The ``history`` parameter can be supplied to ensure this subscriber
        # "catches up" in state. ``full`` (default) can be supplied to
        # apply the full message messages for this publisher. ``tip`` can be
        # supplied to only execute the last message on the queue.
        #
        # A subscriber ID can be passed in to _resume_ a previous subscription.
        # If this method is used, a second parameter can be supplied to
        # specify whether the subscriber should apply this publisher's publish
        # messages. If a publisher ``name`` is passed in without a ``forwards``
        # handler, the publisher will be re-activated.
        #
        # [1]: http://en.wikipedia.org/wiki/Idempotence
        subscribe: (name, forwards, backwards, context, history='full') ->

            if typeof name is 'number'
                if not (subscriber = @subscribers[name]) then return
                subscriber.active = true
                publisher = subscriber.publisher
                publish = forwards or publish
            else
                if not (publisher = @publishers[name])
                    publisher = @publishers[name] = new Publisher name

                else if not forwards or typeof forwards isnt 'function'
                    publisher.active = true
                    return

                subscriber = new Subscriber publisher, forwards, backwards, context

                @subscribers[subscriber.id] = subscriber
                publisher.subscribers.push subscriber

            # Ensure this new subscriber does not go past the hub's current
            # state and does not respond to a former message.
            if publisher.messages.length
                switch history
                    when 'full'
                        messages = publisher.messages
                    when 'tip'
                        messages = [publisher.messages.last()]
                    else
                        messages = []

                for message in messages
                    if message.id > @tip.id
                        break
                    if subscriber.tip and subscriber.tip.id >= message.id
                        continue
                    subscriber.forwards.apply subscriber.context, message.args

                subscriber.tip = message

            # return the subscriber id for later reference in the application
            return subscriber.id

        # Unsubscribe all subscribers for a given ``publisher`` is a publisher name is
        # supplied or unsubscribe a subscriber via their ``id``. If ``remove``
        # is ``true``, all references to the unsubscribed object will be
        # deleted from this hub.
        unsubscribe: (name, hard=false) ->

            if typeof name is 'number'
                subscriber = @subscribers[name]
                if hard
                    delete @subscribers[name]
                    subscribers = subscriber.publisher.subscribers
                    len = subscribers.length
                    while len--
                        if subscriber.id is subscribers[len].id
                            subscribers.splice len, 1
                else
                    subscriber.active = false

            # Handles unsubscribing a whole publisher, i.e. it will no longer
            # broadcast or record new messages.
            else
                if (publisher = @publishers[name])
                    if hard 
                        for subscriber in @publishers[name].subscribers
                            delete @subscribers[subscriber.id]
                        delete @publishers[name]
                    else
                        publisher.active = false

        # The workhorse of the ``publish`` method. For a publisher ``name``, all
        # subscribers will their ``forwards`` handler be executed with ``args``
        # being passed in.
        #
        # Currently, only top-level messages are recorded. If the hub's
        # ``locked`` flag is ``true``, no message is recorded.
        publish: (name, args...) ->

            if not (publisher = @publishers[name])
                publisher = @publishers[name] = new Publisher name
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
                    if not subscriber.active then continue
                    # Create copies of ``args`` to ensure no side-effects
                    # between subscribers.
                    @_transaction subscriber, message, args.slice(0)

            return message and message.id

        # Undo the last message for this hub. Recursively skip any pubs
        # which have an unsubscribed publisher.
        undo: ->

            if (message = @_undos.pop())
                @_redos.push message
                if not message.publisher.active
                    @undo()
                else
                    @_backwards message

        # Redo the next message for this hub. Recursively skip any pubs
        # which have an unsubscribed publisher.
        redo: ->

            if (message = @_redos.pop())
                @_undos.push message
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

        # The logic behind the ``redo`` operation. Each active subscriber for
        # the ``message``'s publisher is targeted.
        #
        # Errors must be caught here to ensure other subscribers are not
        # affected downstream.
        _forwards: (message) ->

            publisher = message.publisher
            if publisher.subscribers.length
                for subscriber in publisher.subscribers
                    if not subscriber.active then continue
                    try
                        subscriber.forwards.apply subscriber.context, message.args.slice(0)
                    finally
                        subscriber.tip = message

            @tip = message

        # The logic behind the ``undo`` operation. Each active subscriber for
        # the ``message``'s publisher is targeted. If the ``backwards`` handler is not
        # defined, the ``forwards`` handler will be used with the previous
        # message's ``args`` for the publisher to mimic the last state.
        #
        # Errors must be caught here to ensure other subscribers are not
        # affected downstream.
        _backwards: (message) ->

            publisher = message.publisher
            if publisher.subscribers.length
                for subscriber in publisher.subscribers
                    if not subscriber.active then continue

                    try
                        if not subscriber.backwards
                            if message.previous
                                subscriber.forwards.apply subscriber.context, message.previous.args.slice(0)
                            else
                                subscriber.forwards.apply subscriber.context
                        else
                            subscriber.backwards.apply subscriber.context, message.args.slice(0)
                    finally
                        subscriber.tip = message

            @tip = message

        # Takes each message in the ``_redos`` and removes and  deferences them
        # from the respective ``publisher`` and the hub.
        _flush: ->
            for _ in @_redos
                message = @_redos.shift()
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
            message = new Message publisher, args, publisher.messages.last()
            @messages[message.id] = message
            publisher.messages.push message

            if @undoStackSize and @_undos.length is @undoStackSize
                @_undos.shift()
            @_undos.push message

            @tip = message


    window.PubSub = PubSub
