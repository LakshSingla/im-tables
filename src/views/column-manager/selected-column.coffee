_ = require 'underscore'

CoreView = require '../../core-view'
Collection = require '../../core/collection'
Templates = require '../../templates'

PathModel = require '../../models/path'

{ignore} = require '../../utils/events'

decr = (i) -> i - 1
incr = (i) -> i + 1

TEMPLATE_PARTS = [
  'column-manager-path-remover',
  'column-manager-position-controls',
  'column-manager-path-name'
]

# (*) Note that when we use the buttons to re-arrange, we do the swapping in
# the event handlers. This is ugly, since we are updating the model _and_ the
# DOM in the same method, rather than having the DOM reflect the model.
# However, the reason for this is as follows: there are two ways to rearrange
# the view - dragging or button clicks. Dragging does not need a re-render,
# just a model update, which is performed in the parent component; Button
# clicks don't need a re-render as such, just a re-arrangement, but
# re-arranging on change:index would cause re-renders when the model is updated
# after drag, causing flicker. Also, we don't really _need_ to re-render the
# whole parent, just swap two neighbouring elements. Since this is easy to do,
# it makes sense to do it here.
#
# As for the moveUp/moveDown methods - these are only available when the view
# is not first/last, this they are null safe with regards to prev/next models.
module.exports = class SelectedColumn extends CoreView

  Model: PathModel

  tagName: 'li'

  className: 'list-group-item im-selected-column'

  template: Templates.templateFromParts TEMPLATE_PARTS

  removeTitle: 'columns.RemoveColumn'

  getData: ->
    isLast = (@model is @model.collection.last())
    _.extend super(), {@removeTitle, isLast, parts: (@parts.pluck 'part')}

  initialize: ->
    super()
    @parts = new Collection
    @listenTo @parts, 'add remove reset', @reRender
    @resetParts()
    @listenTo @model.collection, 'sort', @onCollectionSorted

  modelEvents: ->
    destroy: @stopListeningTo
    'change:parts': @resetParts

  stateEvents: ->
    'change:fullPath': @setFullPathClass

  onCollectionSorted: -> @reRender()

  resetParts: -> @parts.reset({part, id} for part, id in @model.get 'parts')

  postRender: ->
    # Activate tooltips.
    @$('[title]').tooltip container: @$el

  events: ->
    'click .im-remove-view': 'removeView'
    'click .im-move-up': 'moveUp'
    'click .im-move-down': 'moveDown'
    'click': 'toggleFullPath'
    'binned': 'removeView'

  toggleFullPath: -> @state.toggle 'fullPath'

  # Move this view element to the right.
  moveDown: (e) ->
    ignore e
    next = @model.collection.at incr @model.get 'index'
    next.swap 'index', decr
    @model.swap 'index', incr
    @$el.insertAfter @$el.next() # this is ugly, but see *

  # Move this view element to the left.
  moveUp: (e) ->
    ignore e
    prev = @model.collection.at decr @model.get 'index'
    prev.swap 'index', incr
    @model.swap 'index', decr
    @$el.insertBefore @$el.prev() # this is ugly, but see *

  setFullPathClass: ->
    @$el.toggleClass 'im-full-path', @state.get('fullPath')

  removeView: (e) ->
    ignore e
    @model.collection.remove @model
    @model.destroy()
