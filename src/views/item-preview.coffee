_ = require 'underscore'
{Promise} = require 'es6-promise'

Templates = require '../templates'
CoreView = require '../core-view'
CoreModel = require '../core-model'
Options = require '../options'
Collection = require '../core/collection'
PathModel = require '../models/path'
types = require '../core/type-assertions'
getLeaves = require '../utils/get-leaves'

ItemDetails = require './item-preview/details'
ReferenceCounts = require './item-preview/reference-counts'
CountsTitle = require './item-preview/counts-title'

cantFindField = (fld, types) ->
  "Could not determine origin of #{ fld } from [#{ types.join(', ') }]"

class DetailsModel extends PathModel

  constructor: (opts) ->
    super opts.path
    @set _.omit opts, 'path'

class AttrDetailsModel extends DetailsModel

  defaults: -> _.extend super(),
    fieldType: 'ATTR'
    valueOverspill: null
    tooLong: false
    value: null

class RefDetailsModel extends DetailsModel

  defaults: -> _.extend super(),
    fieldType: 'REF'
    values: []

class SortedByName extends Collection

  comparator: 'displayName'

  initialize: ->
    @listenTo @, 'change:displayName', @sort

# the model for the preview needs a type and an id.
class PreviewModel extends CoreModel

  defaults: ->
    types: []
    id: null
    error: null
    phase: 'FETCHING' # one of FETCHING, SUCCESS, ERROR

ERROR = Templates.template 'cell-preview-error'

HIDDEN_FIELDS = ['class', 'objectId'] # We don't show these fields.

# fn version of Array.concat
concat = (xs, ys) -> xs.concat ys
# Accept non-null attrs.
acceptAttr = -> (f, v) -> v? and (not v.objectId) and (f not in HIDDEN_FIELDS)
# Accept references.
acceptRef = -> (f, v) -> v?.objectId

# Define the bits of the service we need.
ServiceType = new types.Structure 'ServiceType',
  root: types.String
  count: types.Function
  findById: types.Function
  fetchModel: types.Function

module.exports = class Preview extends CoreView

  Model: PreviewModel

  className: 'im-cell-preview-inner'

  parameters: ['service']

  parameterTypes:
    service: ServiceType

  initialize: ->
    super()
    @fieldDetails = new SortedByName
    @referenceFields = new SortedByName

  modelEvents: ->
    'change:phase': @reRender
    'change:error': @reRender

  remove: ->
    @removeAllChildren()
    @fieldDetails.close()
    @referenceFields.close()
    delete @fieldDetails
    delete @referenceFields
    super()

  fetching: null

  template: ({phase, error}) -> switch phase
    when 'FETCHING' then @helpers().IndeterminateProgressBar
    when 'ERROR' then ERROR error
    else null

  preRender: -> # Fetch data, but no more than once.
    m = @model
    @fetching ?= @fetchData()
    @fetching.then (-> m.set phase: 'SUCCESS'), (e) ->
      console.error e
      m.set phase: 'ERROR', error: e

  postRender: -> if 'SUCCESS' is @model.get('phase')
    for t in @model.get('types')
      @$el.addClass t

  renderChildren: ->
    itemDetailsTable = new ItemDetails collection: @fieldDetails
    @renderChild 'details', itemDetailsTable

    countsTitle = new CountsTitle collection: @referenceFields
    @renderChild 'counttitle', countsTitle

    referenceCounts = new ReferenceCounts collection: @referenceFields
    @renderChild 'counts', referenceCounts

    @$el.append Templates.clear

  # Fetching requires the InterMine data model, which we name
  # schema here for reasons of sanity (namely collision with the
  # Backbone model located at @model)
  fetchData: -> @service.fetchModel().then (@schema) =>

    gettingDetails = @getAllDetails()

    if Options.get 'ItemDetails.ShowReferenceCounts'
      gettingCounts = @getRelationCounts()
      Promise.all gettingDetails.concat gettingCounts
    else
      Promise.all gettingDetails

  getAllDetails: -> (@getDetails t for t in @model.get 'types')

  getDetails: (type) ->
    id = @model.get('id')
    fields = Options.get ['ItemDetails', 'Fields', @schema.name, type]
    @service.findById(type, id, fields).then @handleItem

  # Reads values from the returned items and adds details objects to the
  # fieldDetails and referenceFields collections, avoiding duplicates.
  handleItem: (item) =>
    coll = @fieldDetails
    testAttr = acceptAttr coll
    testRef = acceptRef coll
    clds = (@schema.classes[t] for t in @model.get 'types')

    for field, value of item when (testAttr field, value)
      @handleAttribute item, clds, field, value

    for field, value of item when (testRef field, value)
      @handleSubObj item, clds, field, value

    return null

  getPathForField: (clds, field) ->
    cld = _.find clds, (c) -> c.fields[field]?
    throw new Error(cantFindField field, _.pick clds, 'name') unless cld?
    path = @schema.makePath "#{ cld.name }.#{ field }"

  # Turns references returned from into name: values pairs
  handleSubObj: (item, clds, field, value) ->
    path = @getPathForField(clds, field)
    values = getLeaves value, HIDDEN_FIELDS
    details = {path, field, values}

    @fieldDetails.add new RefDetailsModel details

  handleAttribute: (item, clds, field, rawValue) ->
    path = @getPathForField(clds, field)
    details = {path, field, value: rawValue}

    if rawValue? and (path.getType() is 'String') or (/Clob/.test path.getType())
      cuttoff = Options.get 'CellCutoff'
      valueString = String rawValue
      tooLong = rawValue.length > cuttoff
      if tooLong # Try and break on whitespace
        snipPoint = valueString.indexOf ' ', cuttoff * 0.9
        snipPoint = cuttoff if snipPoint is -1 # too bad, break here then.
        details.tooLong = true
        details.valueOverspill = valueString.substring(snipPoint)
        details.value = valueString.substring 0, snipPoint

    @fieldDetails.add new AttrDetailsModel details

  getRelationCounts: ->
    types = @model.get 'types'
    root = @service.root
    opts = (Options.get ['ItemDetails', 'Count', root]) ? {}

    countSets = for type in types
      cld = @schema.classes[type]
      for settings in (opts[type] ? (c for c of cld.collections))
        @getRelationCount settings, type

    # Flatten the sets of promises into a single collection.
    countSets.reduce concat, []

  getRelationCount: (settings, type) ->
    id = @model.get 'id'

    if _.isObject settings
      {query, label} = settings
      counter = query id # query is a function from id -> query
      details = (c) -> new CoreModel parts: [label], id: label, displayName: label, count: c
    else
      path = @schema.makePath "#{ type }.#{ settings }"
      return Promise.resolve(true) unless path.getType()?.attributes.id # Skip if no id.
      counter = select: [settings + '.id'], from: type, where: {id}
      details = (c) -> new DetailsModel {path, count: c}

    @service.count counter
            .then details
            .then (d) => @referenceFields.add d if d.get('count')
