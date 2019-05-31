_ = require 'underscore'
Templates = require '../templates'

InputWithLabel = require './input-with-label'

# One word of caution - you should never inject the state into
# this component (except for observation). If two components share
# the same state object, they will probably collide on the validation
# state. The only valid reason to do such a thing would be if two
# such or similar components write to the same value.
module.exports = class SelectWithLabel extends InputWithLabel

  parameters: -> ['model', 'collection', 'attr', 'label', 'optionLabel']

  optionalParameters: -> ['noOptionsMessage'].concat super()

  template: Templates.template 'select-with-label'

  noOptionsMessage: 'core.NoOptions'

  events: ->
    'change select': 'setModelValue'

  collectionEvents: ->
    'add remove reset change': @reRender

  getData: ->
    currentlySelected = @model.get @attr
    _.extend @getBaseData(),
      label: @label
      model: @model.toJSON()
      selected: (list) -> list.name is currentlySelected
      options: @collection.toJSON()
      optionLabel: @optionLabel
      helpMessage: @helpMessage
      noOptionsMessage: @noOptionsMessage
      hasProblem: @state.get('problem')

