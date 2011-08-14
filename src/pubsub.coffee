#
#     PubSub - The PubSub library
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
    # A subscriber is composed of a ``handler`` handler. An optional
    # ``context`` can also be supplied to be the context for the handlers.
    #
    # ``tip`` represents the last message this subscriber has received. A
    # subscriber can be deactivated at any time by setting ``online`` to
    # ``false``. This prevents future messages from being received. If the
    # subscriber comes back _online_, it can optionally receive the queued
    # up messages since it was last subscribed.
    class Subscriber
        constructor: (@publisher, @handler, @context) ->
            @id = suid++
            @online = true
            @tip = null

    # Message
    # -------
    # A message is created and sent by it's ``publisher``. It is composed
    # simply of the arguments passed in on a ``publish`` call. The content
    # will be passed to the subscriber's handlers.
    class Message
        constructor: (@publisher, @content) ->
            @id = muid++
            @previous = @publisher.tip()
            @publisher.messages.push @

        copy: -> @content.slice()

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

    class PubSub
        version: '@VERSION'

        constructor: ->
            @publishers = {}
            @subscribers = {}
            @messages = {}

        _addPublisher: (topic) ->
            if not (publisher = @publishers[topic])
                publisher = new Publisher topic
                @publishers[topic] = publisher
            return publisher

        _addSubscriber: (publisher, handler, context) ->
            subscriber = new Subscriber publisher, handler, context
            @subscribers[subscriber.id] = subscriber
            publisher._add subscriber
            return subscriber

        # Subscribes a handler for the given publisher.
        #
        # An optional ``context`` can be supplied for the ``handler``. 
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
        subscribe: (topic, handler, context, migrate=true) ->
            if topic instanceof Subscriber
                subscriber = topic
                subscriber.online = true
                publisher = subscriber.publisher
                migrate = handler or migrate 
            else
                # Handle the shorthand notation, only handling topic, subscriber
                # and migrate.
                if context in [true, 'tip', false]
                    [migrate, context] = [context, migrate]
                publisher = @_addPublisher topic
                subscriber = @_addSubscriber publisher, handler, context

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
        publish: (topic, content...) ->
            publisher = @_addPublisher topic
            return if not publisher.active
            message = @_record publisher, content
            @_applyToAll message
            return publisher

        # Handles applying a migration for a subscriber depending on it's state
        # relative to the publisher and hub.
        _migrate: (publisher, subscriber, type) ->
            if publisher.messages.length
                if type is 'tip'
                    messages = [publisher.tip()]
                else
                    messages = publisher.messages
                tip = if subscriber.tip then subscriber.tip.id else -1
                @_migrateAll messages, subscriber, tip

        # Applies a forward migration in the ascending order.
        _migrateAll: (messages, subscriber, tip) ->
            for message in messages
                continue if message.id <= tip
                @_applyToOne message, subscriber

        # Broadcasts a mesage to all subscribers of the messages' publisher.
        _applyToAll: (message, tip) ->
            for subscriber in message.publisher.subscribers
                @_applyToOne message, subscriber, tip
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
        _applyToOne: (message, subscriber) ->
            return if not subscriber.online
            subscriber.handler.apply subscriber.context, message.copy()
            subscriber.tip = message

        # Create a new ``message``, store a reference to the last message relative
        # to the publisher.
        _record: (publisher, content) ->
            message = new Message publisher, content
            @messages[message.id] = @
            return message

    window.PubSub = PubSub
