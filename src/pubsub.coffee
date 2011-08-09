#
#     PubSub - The PubSub library with a history API
#     (c) 2011 Byron Ruth
#     PubSub may be freely distributed under the MIT license
#     Version: @VERSION
#

do (window) ->

    # Add helper function to Array
    if not Array::last then Array::last = -> @[this.length - 1]

    # Internal unique identifiers for publications and subscribers
    puid = 1
    suid = 1

    # Sub
    # ---
    # Simple constructor to encapsulate a subscriber
    Sub = (topic, forwards, backwards, context) ->
        @id = suid++
        @topic = topic
        @forwards = forwards
        @backwards = backwards
        @context = context or @
        @active = true
        @last = null
        @



    # Pub
    # ---
    # Simple constructor to encapsulate a top-level publishing
    Pub = (topic, args, prev) ->
        @id = puid++
        @topic = topic
        @args = args
        @prev = prev
        @


    # Topic
    # -----
    # Simple constructor to encapsulate a single topic. all ``subscribers``
    # and publish ``history`` references for this topic are stored here.
    Topic = (name) ->
        @name = name
        @subscribers = []
        @history = []
        @active = true
        @


    # Primary constructor for PubSub hubs
    PubSub = -> new PubSub.fn.init()

    PubSub.version = '@VERSION'

    # Build up the PubSub prototype
    PubSub.fn = PubSub:: =

        constructor: PubSub

        init: ->
            # Registered topics for this hub
            @topics = {}

            # All publications for this hub
            @publications = {}

            # All subscribers for this hub
            @subscribers = {}

            # An undo stack containing ``Pub`` instances. A publication is
            # added to the stack for each successful transaction
            @undoStack = []

            # A redo stack containing ``Pub`` instances. A publication is added
            # to the stack when ``undo`` is called. if transactions occur after
            # items are undone, this stack flushes to ensure consistent behavior
            # for future undos
            @redoStack = []

            # A reference to the last ``Pub`` for this hub
            @last = null

            @

        # Subscribes a handler for the given topic. For [idempotent][1]
        # subscribers, only the ``forwards`` handler is required. For
        # non-idempotent subscribers a ``backwards`` handler must also be
        # defined to ensure consistency during undo/redo operations.
        #
        # An optional ``context`` can be supplied for the ``forwards`` and
        # ``backwards`` handlers. 
        #
        # The ``history`` parameter can be supplied to ensure this subscriber
        # "catches up" in state. ``full`` (default) can be supplied to
        # apply the full publication history for this topic. ``tip`` can be
        # supplied to only execute the last publication on the queue.
        #
        # [1]: http://en.wikipedia.org/wiki/Idempotence
        subscribe: (name, forwards, backwards, context, history='full') ->

            # A ``suid`` can passed in to _resume_ a previous subscription.
            # If this method is used, a second parameter can be supplied to
            # specify whether the subscriber should apply this topic's publish
            # history.
            if typeof name is 'number'
                if not (sub = @subscribers[name]) then return
                sub.active = true
                topic = sub.topic
                publish = forwards or publish
            else
                # Get or create a ``Topic`` instance if one does already exist
                if not (topic = @topics[name])
                    topic = @topics[name] = new Topic name

                sub = new Sub topic, forwards, backwards, context

                @subscribers[sub.id] = sub
                topic.subscribers.push sub

            # handle the various late binding options...
            if history and topic.history.length
                switch history 
                    when 'full'
                        for pub in topic.history
                            # Ensure this subscriber does not go past the
                            # app's current state
                            if pub.id > @last.id
                                break
                            # The subscriber's last publication may be later than
                            # the current ``pub``. If so, skip it.
                            if sub.last and sub.last.id >= pub.id
                                continue

                            # Apply the ``forwards`` handler 
                            sub.forwards.apply sub.context, pub.args

                    when 'tip'
                        pub = topic.history.last()
                        # Ensure this new subscriber does not go past the
                        # app's current state and does not duplicate a response
                        # to a former publication.
                        if pub.id > @last.id then return
                        if sub.last and sub.last.id >= pub.id then return
                        sub.forwards.apply sub.context, pub.args

                sub.last = pub

            # return the subscriber id for later reference in the application
            return sub.id

        # Unsubscribe all subscribers for a given ``topic`` is a topic name is
        # supplied or unsubscribe a subscriber via their ``id``. If ``remove``
        # is ``true``, all references to the unsubscribed object will be
        # deleted from this hub.
        unsubscribe: (name, hard=false) ->

            # Handles unsubscribing a single subscriber.
            if typeof name is 'number'
                sub = @subscribers[name]
                if hard
                    delete @subscribers[name]
                    subscribers = sub.topic.subscribers
                    len = subscribers.length
                    while len--
                        if sub.id is subscribers[len].id
                            subscribers.splice len, 1
                else
                    sub.active = false

            # Handles unsubscribing a whole topic, i.e. it will no longer
            # broadcast or record new publications.
            else
                if (topic = @topics[name])
                    if hard 
                        for sub in @topics[name].subscribers
                            delete @subscribers[sub.id]
                        delete @topics[name]
                    else
                        topic.active = false

        # The workhorse of the ``publish`` method. For a topic ``name``, all
        # subscribers will their ``forwards`` handler be executed with ``args``
        # being passed in.
        #
        # Currently, only top-level publications are recorded. If the hub's
        # ``locked`` flag is ``true``, no publication is recorded.
        publish: (name, args...) ->
            # Get or create a ``Topic`` instance if one does already exist
            if not (topic = @topics[name])
                topic = @topics[name] = new Topic name
            # Ensure the topic is capable of broadcasting.
            else if not topic.active
                return

            pub = null

            # A publication will only be recorded when it's a top-level call.
            # This ensures consistency for the undo/redo stacks
            if not @locked 
                # Flush the redo before adding a new pub to prevent invalid
                # references.
                @_flushRedo()
                # Record this pub to the hub
                pub = @_recordPub(topic, args)

            # If there are any subscribers, execute their respective ``forwards``
            # handlers.
            if topic.subscribers.length
                for sub in topic.subscribers
                    # Skip temporarily unsubscribed subscribers
                    if not sub.active then continue
                    # Create copies of ``args`` to ensure no side-effects
                    # between subscribers.
                    @_transaction sub, pub, args.slice(0)

            return pub and pub.id

        # Encapsulates a _new_ ``forwards`` execution. This hub is locked for
        # the during of this call stack (relative to the handler) to prevent
        # dependent publications from being recorded in the history.
        #
        # Errors must be caught here to ensure other subscribers are not
        # affected downstream.
        _transaction: (sub, pub, args) ->
            if not @locked
                @locked = true
                try
                    sub.forwards.apply sub.context, args
                    sub.last = pub
                finally
                    @locked = false
            else
                try sub.forwards.apply sub.context, args

        _forwards: (pub) ->
            topic = pub.topic
            # if there are any subscribers, execute their respective handlers
            if topic.active and topic.subscribers.length
                for sub in topic.subscribers
                    # Skip temporarily unsubscribed subscribers
                    if not sub.active then continue
                    try
                        sub.forwards.apply sub.context, pub.args.slice(0)
                    finally
                        sub.last = pub

            @last = pub


        _backwards: (pub) ->
            topic = pub.topic
            # if there are any subscribers, execute their respective handlers
            if topic.active and topic.subscribers.length
                for sub in topic.subscribers
                    # Skip temporarily unsubscribed subscribers
                    if not sub.active then continue
                    try
                        # Mimic the prevous publication's call
                        if not sub.backwards
                            if pub.prev
                                sub.forwards.apply sub.context, pub.prev.args.slice(0)
                            else
                                sub.forwards.apply sub.context
                        else
                            sub.backwards.apply sub.context, pub.args.slice(0)
                    finally
                        sub.last = pub

            @last = pub

        undo: ->
            if (pub = @undoStack.pop())
                @redoStack.push pub
                @_backwards pub

        redo: ->
            if (pub = @redoStack.pop())
                @undoStack.push pub
                @_forwards pub

        # Takes each pub in the ``redoStack`` and removes and  deferences them
        # from the hub.
        _flushRedo: ->
            for _ in @redoStack
                pub = @redoStack.shift()
                # pop this pub off of the history stack
                pub.topic.history.pop()
                delete @publications[pub.id]

        _recordPub: (topic, args) ->
            # Create a new pub, store a reference to the last pub relative
            # to the topic. This is for idempotent (or those without a
            # ``backwards`` handler) subscribers.
            pub = new Pub topic, args, topic.history.last()
            # Record this publication for this hub
            @publications[pub.id] = pub
            # Add it to this topic's history for late subscribers
            topic.history.push pub
            # Add it to the undo stack
            @undoStack.push pub
            # Add it to the undo stack
            @last = pub



    PubSub.fn.init:: = PubSub.fn

    window.PubSub = PubSub
