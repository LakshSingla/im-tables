_  = require 'underscore'

Paging = require './paging'
HasDialogues = require '../has-dialogues'
CoreView = require '../../core-view'
Templates = require '../../templates'
Events = require '../../events'

# Dialogues
NewFilterDialogue = require '../new-filter-dialogue'
ExportDialogue = require '../export-dialogue'
LargeTableDisuader = require './large-table-disuader'

# TODO This needs a test/index

module.exports = class PageSizer extends CoreView
  
  @include Paging
  @include HasDialogues

  tagName: 'form'
  className: "im-page-sizer im-table-control form-inline"

  sizes: [[10], [25], [50], [100], [250]] # [0, 'All']]

  parameters: ['getQuery']

  # We need the query because we will pass it on to modal dialogues we open.
  initialize: ->
    super()
    size = @model.get 'size'
    if size? and size not in (s for [s] in @sizes)
      @sizes = [[size, size]].concat @sizes # assign, don't mutate

  events: ->
    'submit': Events.suppress
    'change select': 'changePageSize'

  modelEvents: ->
    'change:size': (m, v) -> @$('select').val v
    'change:count': @reRender

  # Determine the selected size and then apply it.
  # If the size is large enough to be potentially problematic, then first check
  # with the user about what to do, where the options include paging about,
  # adding constraints, exporting data or aborting completely.
  changePageSize: (evt) ->
    input   = @$ evt.target
    size    = parseInt input.val(), 10
    oldSize = @model.get 'size'
    accept = (=> @model.set {size})
    return accept() unless @aboveSizeThreshold size # No need for confirmation.
    pending = @whenAcceptable(size).then (action) =>
      return accept() if action is 'accept'
      input.val oldSize
      switch action
        when 'back' then @goBack 1
        when 'forward' then @goForward 1
        when 'constrain' then @openDialogue new NewFilterDialogue query: @getQuery()
        when 'export' then @openDialogue ExportDialogue query: @getQuery()
        else console.debug 'dismissed dialogue', action

    pending.then null, (e) -> console.error 'Error handling dialogues', e

  # If the new page size is potentially problematic, then check with the user
  # first, rolling back if they see sense. Otherwise, change the page size
  # without user interaction.
  # @param size the requested page size.
  # @return Promise resolved if the new size is acceptable
  whenAcceptable: (size) -> @openDialogue new LargeTableDisuader model: {size}

  template: Templates.template 'page_sizer'

  getData: ->
    count = @model.get 'count'
    size = @model.get 'size'
    sizes = (s for s in @sizes when ((not count?) or (s[0] < count)))

    # If the total count is less than the highest threshold...
    if sizes.length and count < @sizes[@sizes.length - 1][0]
      found = _.find sizes, (next) -> next[0] is count
      # Is our total count one of the page sizes? If so then mutate its label.
      if found 
          found[1]+= found[0] + " (All)"
      else
        sizes.push [count, "#{count} (All)"]
    {size, sizes}

  # An arbitrarily chosen number above which we should be skeptical about the
  # user's judgement. There isn't a huge amount of sense in showing 250 rows on
  # one page - and it will just tax their browser.
  pageSizeFeasibilityThreshold: 250

  # Check if the given size could be considered problematic
  #
  # A size if problematic if it is above the preset threshold, or if it 
  # is a request for all results, and we know that the count is large.
  # @param size The size to assess.
  aboveSizeThreshold: (size) ->
    if size and size >= @pageSizeFeasibilityThreshold
      return true
    if not size # falsy values null, 0 and '' are treated as all
      total = @model.get('count')
      return total >= @pageSizeFeasibilityThreshold
    return false
