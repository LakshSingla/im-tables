d3 = require 'd3-browserify'
$ = require 'jquery'
_ = require 'underscore'

Options = require '../../options'
Messages = require '../../messages'
require '../../messages/summary' # include the summary messages.
VisualisationBase = require './visualisation-base'

NULL_SELECTION_WIDTH = 25

# Helper that constructs a scale fn from the given input domain to the given output range
scale = (input, output) -> d3.scale.linear().domain(input).range(output)

# A function that takes the number of a bucket and a function that will turn that into
# a value in the continous range of values for the paths and produces an object saying
# what the range of values are for the bucket.
# (Function<int, Number>, int) -> {min :: Number, max :: Number}
bucketRange = (bucketVal, bucket) ->
  [min, max] = (bucketVal(bucket + delta) for delta in [0, 1])
  {min, max}

# Function that enforces limits on a value.
limited = (min, max) -> (x) ->
  if x < min
    min
  else if x > max
    max
  else
    x

module.exports = class NumericDistribution extends VisualisationBase

  className: "im-numeric-distribution"

  # Dimensions of the chart.
  leftMargin: 25
  bottomMargin: 18
  rightMargin: 14
  chartHeight: 70

  # Flag so we know if we are selecting paths.
  __selecting_paths: false

  # The rubber-band selection.
  selection: null

  # Range is shared by other components, so we accept it from the outside.
  # We listen to changes on the range and respond by drawing a selection box.
  initialize: ({@range}) ->
    super()
    @listenTo @range, 'change reset', @onChangeRange

  # Things to check when we are initialised.
  invariants: ->
    hasRange: "No range"
    hasHistogramModel: "Wrong model: #{ @model }"

  hasRange: -> @range?

  hasHistogramModel: -> @model?.getHistogram?

  # The rendering logic. This component renders a numeric histogram.
  # 
  # the histogram is a list of values, eg: [1, 3, 5, 0, 10, 7, 4],
  # these represent a set of equal width buckets across the range
  # of the available values. Buckets are 1-indexed (in the example
  # above there are 7 buckets, labelled 1-7). The number of buckets
  # is available on the SummaryItems model as 'buckets', the
  # histogram can be accessed with SummaryItems::getHistogram.

  # Each bucket is represented by a rect which is placed on the canvas.
  selectNodes: (chart) -> chart.selectAll 'rect'

  # For convenience we store the bucket number with the count, although it
  # is trivial to calculate from the index. The range is also stored, which
  # is more of a faff to calculate (since you need access to the scales)
  getChartData: (scales) ->
    scales ?= @getScales()
    for c, i in @model.getHistogram()
      {count: c, bucket: (i + 1), range: (bucketRange scales.bucketToVal, i + 1)}

  # Set properties that we need access to the DOM to calculate.
  initChart: ->
    super()
    @bucketWidth = (@model.get('max') - @model.get('min')) / @model.get('buckets')
    @stepWidth = (@chartWidth - (@leftMargin + 1)) / @model.get('buckets')

  # There are five separate things here:
  #  - x positions (the graphical position horizontally)
  #  - y positions (the graphical position vertically)
  #  - values (the values the path can hold - a continous range)
  #  - buckets (the number of the equal width buckets a value falls into)
  #  - counts (the number of values in a bucket)
  # The x scale is BucketNumber -> XPos
  # The y scale is Count -> YPos
  # We also need reverse scales for finding value for an x-position.
  getScales: ->
    {min, max} = @model.pick 'min', 'max'
    n = @model.get 'buckets'
    histogram = @model.getHistogram()
    most = d3.max histogram

    # These are the five separate things.
    counts = [0, most]
    values = [min, max]
    buckets = [1, n + 1]
    xPositions = [@leftMargin, @chartWidth - @rightMargin]
    yPositions = [0, @chartHeight - @bottomMargin]

    # wrapper around a ->val scale that applies the appropriate rounding and limits
    toVal = (inputs) -> _.compose (limited min, max), (scale inputs, values)

    scales = # return:
      x: (scale buckets, xPositions) # A scale from bucket -> x
      y: (scale counts, yPositions)  # A scale from count -> y
      valToX: (scale values, xPositions) # A scale from value -> x
      xToVal: (toVal xPositions) # A scale from x -> value
      bucketToVal: (toVal buckets) # A scale from bucket -> min val

  # Does the path represent a whole number value, such as an integer?
  isIntish: -> @model.get('type') in ['int', 'Integer', 'long', 'Long', 'short', 'Short']

  # Return a function we can use to round values we calculate from x positions.
  getRounder: -> if @isIntish() then Math.round else _.identity

  # The things we do to new rectangles.
  enter: (selection, scales) ->
    # For performance it is best to pass this in, but this line makes it clear what scales
    # refers to.
    scales ?= @getScales()
    container = @el
    round = @getRounder()
    h = @chartHeight

    # When the user clicks on a bar, set the selected range to the range
    # the bar covers.
    barClickHandler = (d, i) =>
      if d.count > 0
        @range.set d.range
      else
        @range.nullify()

    # Get the tooltip text for the bar.
    getTitle = ({range: {min, max}, count}) ->
      Messages.getText 'summary.Bucket', {count, range: {min: (round min), max: (round max)}}

    # The inital state of the bars is 0-height in the correct x position, with click
    # handlers and tooltips attached.
    selection.append('rect')
             .attr 'x', (d, i) -> scales.x d.bucket # - 0.5 # subtract half a bucket to be at start
             .attr 'width', (d) -> Math.max 0, (scales.x d.bucket + 1) - (scales.x d.bucket)
             .attr 'y', h - @bottomMargin # set the height to 0 initially.
             .attr 'height', 0
             .classed 'im-bucket', true
             .classed 'im-null-bucket', (d) -> d.bucket is null # I suspect this is pointless.
             .on 'click', barClickHandler
             .each (d) -> $(@).tooltip {container, title: getTitle d}

  update: (selection, scales) ->
    scales ?= @getScales()
    h = @chartHeight
    bm = @bottomMargin
    {Duration, Easing} = Options.get('D3.Transition')
    height = (d) -> scales.y d.count
    selection.transition()
             .duration Duration
             .ease Easing
             .attr 'height', height
             .attr 'y', (d) -> h - bm - (height d) - 0.5

  # Axes are drawn with tick-lines.
  drawAxes: (chart, scales) ->
    chart ?= @getCanvas()
    scales ?= @getScales()
    bottom = @chartHeight - @bottomMargin - .5
    container = @el

    # Draw a line for the average, if we are meant to.
    if Options.get('Facets.DrawAverageLine')
      chart.append('line')
          .classed 'average', true
          .attr 'x1', scales.valToX(@model.get 'average')
          .attr 'x2', scales.valToX(@model.get 'average')
          .attr 'y1', 0
          .attr 'y2', bottom
          .each -> $(@).tooltip {container, title: Messages.getText('summary.Average')}

    # Draw a line across the bottom of the chart.
    chart.append('line')
         .classed 'axis', true
         .attr 'x1', 0
         .attr 'x2', @chartWidth
         .attr 'y1', bottom
         .attr 'y2', bottom

    axis = chart.append('svg:g')

    ticks = scales.x.ticks @model.get('buckets')

    # Draw a tick line for each bucket.
    axis.selectAll('line').data(ticks)
        .enter()
          .append('svg:line')
          .classed 'tick-line', true
          .attr 'x1', scales.x
          .attr 'x2', scales.x
          .attr 'y1', @chartHeight - (@bottomMargin * 0.75)
          .attr 'y2', @chartHeight - @bottomMargin

  # Events, with their definitions and handlers.
  # Also, each bar has a handler (see ::enter) and the range itself
  # has handlers (see ::initialize)
  events: ->
    'mouseout': => @__selecting_paths = false # stop selecting when the mouse leaves the el.

  # Draw the rubber-band selection over the top of the canvas. The selection
  # is a full height box starting at x and extending to the right for width pixels.
  drawSelection: (x, width) ->
    if (not x?) or (x <= 0) or (width >= @chartWidth)
      return @removeSelection()
      
    # Create it if it doesn't exist.
    @selection ?= @getCanvas().append('svg:rect')
                              .attr('y', 0)
                              .attr('height', @chartHeight * 0.9)
                              .classed('rubberband-selection', true)
    # Change its width and x position.
    @selection.attr('x', x).attr('width', width)

  # When the range changes, draw the selection box, if we need to.
  onChangeRange: ->
    if @shouldDrawBox()
      scales = @getScales()
      {min, max} = @range.toJSON()
      start = scales.valToX min
      width = (scales.valToX max) - start
      @drawSelection(start, width)
    else
      @removeSelection()

  removeSelection: ->
    @selection?.remove()
    @selection = null

  # We should draw the selection box when there is a selection.
  shouldDrawBox: -> @range.isNotAll()

  remove: -> # remove the chart if necessary.
    @removeSelection()
    @paper?.remove()
    super()

