_ = require 'underscore'

CoreView = require '../../core-view'
CoreModel = require '../../core-model'
Collection = require '../../core/collection'
Templates = require '../../templates'

ClassSet = require '../../utils/css-class-set'
Counter = require '../../utils/count-executor'
PathModel = require '../../models/path'

# The four dialogues of the apocalypse
AppendPicker = require './append-from-selection'
CreatePicker = require './create-from-selection'
AppendFromPath = require './append-from-path'
CreateFromPath = require './create-from-path'

require '../../messages/lists'


class Paths extends Collection

  model: PathModel

class SelectableNode extends CoreView

  parameters: ['query', 'model', 'showDialogue', 'highLight']

  tagName: 'li'

  modelEvents: -> 'change:displayName change:typeName': @reRender

  stateEvents: -> 'change:count': @reRender

  Model: PathModel

  template: Templates.template 'list-dialogue-button-node'

  events: ->
    click: @openDialogue
    'mouseenter a': -> _.defer => @highLight @model.get('path')
    'mouseout a': -> @highLight null

  initialize: ->
    super()
    @query.summarise @model.get 'id'
          .then ({stats}) => @state.set count: stats.uniqueValues

  openDialogue: ->
    args = {@query, path: @model.get('id')}
    @showDialogue args

module.exports = class ListDialogueButton extends CoreView

  tagName: 'div'

  className: 'btn-group list-dialogue-button'

  template: Templates.template 'list-dialogue-button'

  parameters: ['query', 'selected']

  optionalParameters: ['tableState']

  tableState: new CoreModel

  initState: ->
    @state.set action: 'create', authenticated: false, disabled: false

  stateEvents: ->
    'change:action': @setActionButtonState
    'change:authenticated': @setVisible
    'change:disabled': @onChangeDisabled

  events: ->
    'click .im-create-action': @setActionIsCreate
    'click .im-append-action': @setActionIsAppend
    'click .im-pick-items': @startPicking

  initialize: ->
    super()
    @initBtnClasses()
    @paths = new Paths
    # Reversed, because we prepend them in order to the menu.
    @query.getQueryNodes().reverse().forEach (n) => @paths.add new PathModel n
    @query.service.whoami().then (u) => @state.set authenticated: (!!u)
    Counter.count @query # Disable export if no results or in error.
           .then (count) => @state.set disabled: count is 0
           .then null, (err) => @state.set disabled: true, error: err

  getData: -> _.extend super(), @classSets, paths: @paths.toJSON()

  postRender: ->
    @setVisible()
    @onChangeDisabled()
    menu = @$ '.dropdown-menu'
    highLight = (p) => @tableState.set highlitNode: p
    showDialogue = (args) => @showPathDialogue args
    @paths.each (model, i) =>
      node = new SelectableNode {@query, model, showDialogue, highLight}
      @renderChild "path-#{ i }", node, menu, 'prepend'

  onChangeDisabled: -> @$('.btn').toggleClass 'disabled', @state.get 'disabled'

  setVisible: -> @$el.toggleClass 'im-hidden', (not @state.get 'authenticated')

  setActionIsCreate: (e) ->
    e.stopPropagation()
    e.preventDefault()
    @state.set action: 'create'

  setActionIsAppend: (e) ->
    e.stopPropagation()
    e.preventDefault()
    @state.set action: 'append'

  showDialogue: (Dialogue, args) ->
    dialogue = new Dialogue args
    @renderChild 'dialogue', dialogue
    action = @state.get 'action'
    handler = (outcome) => (result) =>
      @trigger "#{ outcome }:#{ action }", result
      @trigger outcome, action, result
    dialogue.show().then (handler 'success'), (handler 'failure')

  showPathDialogue: (args) ->
    action = @state.get 'action'
    Dialogue = switch action
      when 'append' then AppendFromPath
      when 'create' then CreateFromPath
      else throw new Error "Unknown action: #{ action }"
    @showDialogue Dialogue, args

  startPicking: ->
    action = @state.get 'action'
    args = {collection: @selected, service: @query.service}
    Dialogue = switch action
      when 'append' then AppendPicker
      when 'create' then CreatePicker
      else throw new Error "Unknown action: #{ action }"
    @tableState.set selecting: true
    stopPicking = =>
      @tableState.set selecting: false
      @selected.reset()
    @showDialogue(Dialogue, args).then stopPicking, stopPicking

  setActionButtonState: ->
    action = @state.get 'action'
    @$('.im-create-action').toggleClass 'active', action is 'create'
    @$('.im-append-action').toggleClass 'active', action is 'append'

  initBtnClasses: ->
    @classSets = {}
    @classSets.createBtnClasses = new ClassSet
      'im-create-action': true
      'btn btn-default': true
      active: => @state.get('action') is 'create'
    @classSets.appendBtnClasses = new ClassSet
      'im-append-action': true
      'btn btn-default': true
      active: => @state.get('action') is 'append'

