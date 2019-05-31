_ = require 'underscore'
CoreView = require '../../core-view'
Messages = require '../../messages'
PathModel = require '../../models/path'

require '../../messages/constraints'

module.exports = class AdderButton extends CoreView

  Model: PathModel
  
  tagName: 'button'

  className: 'btn btn-primary im-add-constraint'

  optionalParameters: ['hideType']

  hideType: false

  template: (data) -> _.escape Messages.getText 'constraints.AddConFor', data

  getData: -> _.extend super(), {@hideType}

  modelEvents: -> change: @reRender

  events: -> click: -> @trigger 'chosen', @model.get 'path'

