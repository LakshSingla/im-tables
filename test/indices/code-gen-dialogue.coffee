require 'imtables/shim'
$ = require 'jquery'

Dialogue = require 'imtables/views/code-gen-dialogue'

renderQueries = require '../lib/render-queries.coffee'
renderQueryWithCounter = require '../lib/render-query-with-counter-and-displays.coffee'
model = lang: 'py'
done = console.log.bind(console, 'SUCCESS')
fail = console.error.bind(console)
create = (query) -> new Dialogue {query, model}
showDialogue = (dialogue) -> dialogue.show().then done, fail

queries = [
  {
    name: "older than 35"
    select: ["name", "manager.name", "employees.name", "employees.age"]
    from: "Department"
    where: [ [ "employees.age", ">", 35 ] ]
  }
]

renderQuery = renderQueryWithCounter create, showDialogue

$ -> renderQueries queries, renderQuery
