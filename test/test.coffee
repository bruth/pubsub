test 'Publisher', 7, ->
    hub = new PubSub

    hub.publish 'foo', 1
    hub.publish 'foo', 2
    p = hub.publish 'foo', 3
    equals p.messages.length, 3
    equals p.tip().content[0], 3

    p.active = false
    ok not hub.publish 'foo', 'nope'
    equals p.messages.length, 3, 'not recorded'
    p.active = true
    ok hub.publish 'foo', 'yep'

    p = hub.publish 'bar', 1, 2, 3, 4
    equals p.messages.length, 1

    p = hub.publish 'baz', ->
    equals p.messages.length, 1


test 'Subscriber', 6, ->
    hub = new PubSub
    output = null

    # basic usage
    s1 = hub.subscribe 'foo', (msg) -> output = msg
    # custom context
    hub.subscribe 'foo', ((msg) -> output = "#{@} #{msg}"), 'goober'
    s2 = hub.subscribe 'foo', (msg) -> output = "moto #{msg}"

    ok hub.publishers.foo, 'a new topic has been added'
    equals s1.publisher.subscribers.length, 3, 'the subscriber has been added'
    equals output, null, 'nothing changed yet'

    # offline
    s2.online = false

    hub.publish 'foo', 4
    ok s1.tip
    ok not s2.tip
    equals output, 'goober 4'


test 'Subscribe - late', 6, ->
    hub = new PubSub
    output = 0

    hub.publish 'foo'
    hub.publish 'foo'
    p3 = hub.publish 'foo'

    sub1 = hub.subscribe 'foo', ->
        output++

    equals output, 3, 'all history up to this point'
    equals sub1.tip, p3.tip(), 'last pub is referenced'

    sub2 = hub.subscribe 'foo', ->
        output++
    , 'tip'

    equals output, 4, 'only the tip of the history was executed'
    equals sub2.tip, p3.tip(), 'last pub is referenced'

    sub3 = hub.subscribe 'foo', ->
        output++
    , false

    equals output, 4, 'none of the history is applied'
    equals sub3.tip, null, 'no pub has been applied'


test 'Unsubscribe & Re-subscribe', 3, ->
    hub = new PubSub
    output = 0

    s1 = hub.subscribe 'foo', ->
        output++

    hub.publish 'foo'
    hub.publish 'foo'

    equals output, 2, '2 pubs'

    hub.unsubscribe s1

    hub.publish 'foo'
    hub.publish 'foo'

    equals output, 2, 'still 2 pubs'

    hub.subscribe s1

    equals output, 4, 'resumed to 4 pubs'

