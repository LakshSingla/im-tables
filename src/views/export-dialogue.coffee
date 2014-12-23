_ = require 'underscore'

Model = require '../core-model'
Modal = require './modal'
ConstraintAdder = require './constraint-adder'
Messages = require '../messages'
Templates = require '../templates'

Menu = require './export-dialogue/tab-menu'
FormatControls = require './export-dialogue/format-controls'
RowControls = require './export-dialogue/row-controls'

class ExportModel extends Model

  defaults: ->
    format: 'tab'
    start: 0
    size: null

# A complex dialogue that delegates the configuration of different
# export parameters to subviews.
module.exports = class ExportDialogue extends Modal

  Model: ExportModel

  className: -> 'im-export-dialogue ' + super

  initialize: ({@query}) ->
    super
    @state.set tab: 'format', dest: 'FAKE DATA'
    @listenTo @state, 'change:tab', @renderMain

  title: ->
    Messages.getText 'ExportTitle', {name: @query.name}

  primaryAction: -> Messages.getText 'ExportButton'

  body: Templates.template 'export_dialogue'

  getMain: ->
    switch @state.get('tab')
      when 'format' then FormatControls
      when 'rows' then RowControls
      else FormatControls

  renderMain: ->
    Main = @getMain()
    @renderChild 'main', (new Main {@model, @query}), @$ 'div.main'

  postRender: ->
    @renderChild 'menu', (new Menu {model: @state}), @$ 'nav.menu'
    @renderMain()
    super