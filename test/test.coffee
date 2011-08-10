test 'Publish', 3, ->
    hub = new PubSub
    output = null

    hub.subscribe 'foo', (msg) ->
        output = msg

    hub.publish 'foo', 'hello moto'
    equals output, 'hello moto', 'updated'

    hub.publish 'bar', 'something new'
    equals output, 'hello moto', 'nothing changed due to a new topic'

    hub.publish 'foo', 'and again'
    equals output, 'and again', 'updated'


test 'Subscribe', 3, ->
    hub = new PubSub
    output = null

    sid = hub.subscribe 'foo', (msg) ->
        output = msg

    ok hub.publishers.foo, 'a new topic has been added'
    ok hub.subscribers[sid], 'the subscriber has been added'
    equals output, null, 'nothing changed yet'


test 'Subscribe - late', 6, ->
    hub = new PubSub
    output = 0

    hub.publish 'foo'
    hub.publish 'foo'
    p3 = hub.publish 'foo'

    s1 = hub.subscribe 'foo', ->
        output++

    equals output, 3, 'all history up to this point'
    equals hub.subscribers[s1].tip.id, p3, 'last pub is referenced'

    s2 = hub.subscribe 'foo', ->
        output++
    , null, null, 'tip'

    equals output, 4, 'only the tip of the history was executed'
    equals hub.subscribers[s2].tip.id, p3, 'last pub is referenced'

    s3 = hub.subscribe 'foo', ->
        output++
    , null, null, false

    equals output, 4, 'none of the history is applied'
    equals hub.subscribers[s3].tip, null, 'no pub has been applied'


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


test 'Partial Redo, New Pubs', 11, ->
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


test 'Non-Idempotent Partial Redo, New Pubs', 11, ->
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
