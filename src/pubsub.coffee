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

    PubSub = -> new PubSub.fn.init()

    PubSub.version = '@VERSION'

    PubSub.fn = PubSub:: =

        constructor: PubSub

        init: ->
            @topics = {}
            @publications = {}
            @subscribers = {}
            @undoStack = []
            @redoStack = []
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
        # A sub IDcan passed in to _resume_ a previous subscription.
        # If this method is used, a second parameter can be supplied to
        # specify whether the subscriber should apply this topic's publish
        # history. If a topic ``name`` is passed in without a ``forwards``
        # handler, the topic will be re-activated.
        #
        # [1]: http://en.wikipedia.org/wiki/Idempotence
        subscribe: (name, forwards, backwards, context, history='full') ->

            if typeof name is 'number'
                if not (sub = @subscribers[name]) then return
                sub.active = true
                topic = sub.topic
                publish = forwards or publish
            else
                if not (topic = @topics[name])
                    topic = @topics[name] = new Topic name

                else if not forwards or typeof forwards isnt 'function'
                    topic.active = true
                    return

                sub = new Sub topic, forwards, backwards, context

                @subscribers[sub.id] = sub
                topic.subscribers.push sub

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

            if not (topic = @topics[name])
                topic = @topics[name] = new Topic name
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

        # Undo the last publication for this hub. Recursively skip any pubs
        # which have an unsubscribed topic.
        undo: ->

            if (pub = @undoStack.pop())
                @redoStack.push pub
                if not pub.topic.active
                    @undo()
                else
                    @_backwards pub

        # Redo the next publication for this hub. Recursively skip any pubs
        # which have an unsubscribed topic.
        redo: ->

            if (pub = @redoStack.pop())
                @undoStack.push pub
                if not pub.topic.active
                    @redo()
                else
                    @_forwards pub

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

        # The logic behind the ``redo`` operation. Each active subscriber for
        # the ``pub``'s topic is targeted.
        #
        # Errors must be caught here to ensure other subscribers are not
        # affected downstream.
        _forwards: (pub) ->

            topic = pub.topic
            if topic.subscribers.length
                for sub in topic.subscribers
                    if not sub.active then continue
                    try
                        sub.forwards.apply sub.context, pub.args.slice(0)
                    finally
                        sub.last = pub

            @last = pub

        # The logic behind the ``undo`` operation. Each active subscriber for
        # the ``pub``'s topic is targeted. If the ``backwards`` handler is not
        # defined, the ``forwards`` handler will be used with the previous
        # publication's ``args`` for the topic to mimic the last state.
        #
        # Errors must be caught here to ensure other subscribers are not
        # affected downstream.
        _backwards: (pub) ->

            topic = pub.topic
            if topic.subscribers.length
                for sub in topic.subscribers
                    if not sub.active then continue

                    try
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

        # Takes each pub in the ``redoStack`` and removes and  deferences them
        # from the respective ``topic`` and the hub.
        _flushRedo: ->

            for _ in @redoStack
                pub = @redoStack.shift()
                pub.topic.history.pop()
                delete @publications[pub.id]

        # Create a new ``pub``, store a reference to the last pub relative
        # to the topic. This is for idempotent (or those without a
        # ``backwards`` handler) subscribers.
        # 
        # This ``pub`` is added to the topic history, the undo stack and
        # is set as the hub's ``last`` pub.
        _recordPub: (topic, args) ->

            pub = new Pub topic, args, topic.history.last()
            @publications[pub.id] = pub
            topic.history.push pub
            @undoStack.push pub
            @last = pub



    PubSub.fn.init:: = PubSub.fn

    window.PubSub = PubSub
