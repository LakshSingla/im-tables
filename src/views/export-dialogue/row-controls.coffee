_ = require 'underscore'
View = require '../../core-view'
Messages = require '../../messages'
Templates = require '../../templates'

class LabelView extends View

  RERENDER_EVENT: 'change'

  tagName: 'span'

class SizeLabel extends LabelView

  getData: -> _.extend super, size: (@model.get('size') or Messages.getText('rows.All'))

  template: _.template """
    <%- Messages.getText('export.param.Size', {size: size}) %>
  """

class OffsetLabel extends LabelView

  template: _.template """
    <%- Messages.getText('export.param.Start', {start: start}) %>
  """

class ResetButton extends View

  RERENDER_EVENT: 'change'

  getData: -> _.extend super, isAll: not (@model.get('start') or @model.get('size'))

  template: _.template """
    <button type="button"
            <%= (isAll) ? 'disabled' : void 0 %>
            class="btn btn-default btn-reset">
            <%- Messages.getText('Reset') %>
    </button>
  """

  events: ->
    'click button': 'reset'

  reset: ->
    @model.set start: 0, size: null

module.exports = class RowControls extends View

  RERENDER_EVENT: 'change:max'

  initialize: ({@query}) ->
    super
    @model.set max: null unless @model.has 'max'
    @listenTo @model, 'change:size', @updateLabels
    @query.count().then (c) => @model.set max: c
    @listenTo @model, 'change:size change:start', @updateInputs

  tagName: 'form'

  template: Templates.template 'export_row_controls'

  events: ->
    'change input[name=size]': 'onChangeSize'
    'change input[name=start]': 'onChangeStart'

  updateInputs: ->
    for prop in ['size', 'start']
      @$("input[name=#{ prop }]").val @model.get prop

  onChangeSize: ->
    size = parseInt(@$('input[name=size]').val(), 10)
    if (not size) or (size is @model.get('max'))
      @model.set size: null
    else
      @model.set size: size

  onChangeStart: ->
    @model.set start: parseInt(@$('input[name=start]').val(), 10)

  postRender: ->
    @renderChild 'size', (new SizeLabel {@model}), @$ '.size-label'
    @renderChild 'start', (new OffsetLabel {@model}), @$ '.start-label'
    @renderChild 'reset', (new ResetButton {@model}), @$ '.im-reset'
