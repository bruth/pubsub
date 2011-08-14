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
    hub.subscribe 'foo', ((msg) -> output = "#{@} #{msg}"), null, 'goober'
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
    , null, null, 'tip'

    equals output, 4, 'only the tip of the history was executed'
    equals sub2.tip, p3.tip(), 'last pub is referenced'

    sub3 = hub.subscribe 'foo', ->
        output++
    , null, null, false

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


test 'Idempotent Undo/Redo', 11, ->
    hub = new PubSub
    output = undefined

    hub.subscribe 'foo', (msg) ->
        output = msg

    hub.undo()
    equals output, undefined, 'cannot go backward'

    hub.publish 'foo', 'hello moto'
    equals output, 'hello moto', 'updated'

    hub.undo()
    equals output, undefined, 'handler called with no arguments'
    hub.redo()
    equals output, 'hello moto', 'stays the same'

    hub.publish 'foo', 'and again'
    equals output, 'and again', 'updated'

    hub.undo()
    equals output, 'hello moto', 'back 1'
    hub.redo()
    equals output, 'and again', 'forward 1'

    hub.publish 'foo', 'once more'
    equals output, 'once more', 'updated'

    hub.undo()
    hub.undo()
    equals output, 'hello moto', 'back 2'

    hub.redo()
    hub.redo()
    equals output, 'once more', 'back to tip'

    hub.redo()
    equals output, 'once more', 'cannot go forward'


test 'Undo/Redo', 12, ->
    hub = new PubSub
    Counter = ->
        @count = 0
        @incr = => @count++
        @decr = => @count--
        @

    counter = new Counter

    hub.subscribe 'foo', counter.incr, counter.decr

    hub.undo()
    equals counter.count, 0, 'cannot go backward'

    hub.publish 'foo'
    equals counter.count, 1, '+1'

    hub.undo()
    equals counter.count, 0, '-1'
    hub.undo()
    equals counter.count, 0, 'still cannot go backward'
    hub.redo()
    equals counter.count, 1, 'back to +1'

    hub.publish 'foo'
    equals counter.count, 2, '+1'

    hub.undo()
    equals counter.count, 1, '-1'
    hub.redo()
    equals counter.count, 2, '+1'

    hub.publish 'foo'
    equals counter.count, 3, '+1'

    hub.undo()
    hub.undo()
    equals counter.count, 1, '-2'

    hub.redo()
    hub.redo()
    equals counter.count, 3, 'back to tip'

    hub.redo()
    equals counter.count, 3, 'cannot go forward'


test 'Partial Redo, New Pubs', 12, ->
    hub = new PubSub
    output = undefined

    hub.subscribe 'foo', (msg) ->
        output = msg

    hub.undo()
    equals output, undefined, 'cannot go backward'

    hub.publish 'foo', 'hello moto'
    equals output, 'hello moto', 'updated'

    hub.undo()
    equals output, undefined, 'handler called with no arguments'
    hub.redo()
    equals output, 'hello moto', 'stays the same'

    hub.publish 'foo', 'and again'
    equals output, 'and again', 'updated'

    hub.undo()
    equals output, 'hello moto', 'back 1'

    hub.publish 'foo', 'new path'
    equals output, 'new path', 'updated'
    equals hub.redos.length, 0, 'redos flushed'

    hub.redo()
    equals output, 'new path', 'stays the same'

    hub.undo()
    hub.undo()
    equals output, undefined, 'back 2'

    hub.redo()
    hub.redo()
    equals output, 'new path', 'back to tip'

    hub.redo()
    equals output, 'new path', 'cannot go forward'


test 'Non-Idempotent Partial Redo, New Pubs', 12, ->
    hub = new PubSub
    Counter = ->
        @count = 0
        @incr = => @count++
        @decr = => @count--
        @

    counter = new Counter

    hub.subscribe 'foo', counter.incr, counter.decr

    hub.undo()
    equals counter.count, 0, 'cannot go backward'

    hub.publish 'foo'
    equals counter.count, 1, '+1'

    hub.undo()
    equals counter.count, 0, '-1'
    hub.undo()
    equals counter.count, 0, 'still cannot go backward'
    hub.redo()
    equals counter.count, 1, 'back to +1'

    hub.publish 'foo'
    equals counter.count, 2, '+1'

    hub.undo()
    equals counter.count, 1, '-1'

    hub.publish 'foo'
    equals hub.redos.length, 0, 'redos flushed'
    hub.publish 'foo'
    equals counter.count, 3, '+2'

    hub.redo()
    equals counter.count, 3, 'stays the same'

    hub.undo()
    hub.undo()
    equals counter.count, 1, '-2'

    hub.redo()
    hub.redo()
    equals counter.count, 3, 'back to tip'


test 'Nested Publish Calls', ->
    hub = new PubSub

    Counter = ->
        @count = 0
        @incr = => ++@count
        @decr = => --@count
        @

    c1 = new Counter
    c2 = new Counter

    hub.subscribe 'foo'
        , ->
            hub.publish 'bar', c1.incr()
        , ->
            hub.publish 'bar', c1.decr()

    hub.subscribe 'bar'
        , ->
            c2.incr() if c2.count < 3
        , ->
            c2.decr() if c2.count > 0


    hub.publish 'foo'
    equals c1.count, 1
    equals c2.count, 1

    hub.undo()
    equals c1.count, 0
    equals c2.count, 0

    hub.redo()
    equals c1.count, 1
    equals c2.count, 1

    hub.publish 'foo'
    hub.publish 'foo'
    hub.publish 'foo'

    equals c1.count, 4
    equals c2.count, 3

    hub.undo()
    hub.undo()

    equals c1.count, 2
    equals c2.count, 1

    out = 0
    hub.subscribe 'bar', (count) -> out = Math.pow 2, count

    equals out, 0
    hub.redo()
    equals out, 8

    hub.undo()
    equals out, 4
