_ = require "lodash"
obj_keys = _.keys
obj_values = _.values
{ filter, flatten, has, merge, omit, reduce } = _
{ indent, json, log, p, pjson, type } = require 'lightsaber'

class Node

  @KEY = KEY = 'key'

  constructor: (data={}, options={}) ->
    DEFAULT_OPTIONS =
      id: false
    options = merge DEFAULT_OPTIONS, options
    @_attrs = []
    @_add_dict_or_array data
    if options.id
      @meta 'id', Node.random_key(), skip_if_exists: 'key'

  meta: (key, value, options={}) ->
    if _.size(arguments) is 0
      @_get_meta_attrs()
    else
      @add_data @_meta_ize(key), value, options

  _add_dict_or_array: (data) ->
    if type(data) is 'array'
      for item in data
        @add_dict item
    else
      @add_dict data

  add_dict: (dict) ->
    if type(dict) isnt 'object'
      throw "Expected 'object', got unexpected type '#{type(dict)}' for '#{pjson dict}'"
    for own key, value of dict
      @add_data key, value

  add_data_unless_exists: (key, value) ->
    @add_data key, value, skip_if_exists: 'value'

  # alias for add_data
  add_value: -> @add_data arguments...

  add_data: (key, value, options={}) ->
    return if options.skip_if_exists is 'key'   and @_has key
    return if options.skip_if_exists is 'value' and @_has key, value
    if type(value) is 'array'
      for item in value
        @_add_attr key, item, options
    else
      @_add_attr key, value, options

  increment: (key, amount = 1) ->
    unless type(key) is 'string'
      throw "Expected key to be of type 'string', got: '#{type(key)}'"
    success = false
    for attr in @_attrs
      if _key(attr) is key and type(_value(attr)) is 'number'
        attr[_key attr] = _value(attr) + amount
        success = true
    if not success
      @_add_attr key, amount

  label: ->
    @_get_key() ? @id()

  id: ->
    for attr in @_attrs
      if _key(attr) is '_id'
        return _value(attr)
    return null # throw "no _id property found for #{pjson @}"

  # pretty printed json
  to_json: ->
    attributes = for attribute in @data()
      for key, value of attribute
        "{ #{json key}: #{json value} }"
    attributes = attributes.join(",\n")
    "[\n#{indent attributes}\n]"

  data: (options = {}) ->
    _friendly_sort @_filter_attrs(options)

  # omit metadata: anything starting with underscore
  props: ->
    _.filter @_attrs, (attr) -> not _.startsWith _key(attr), '_'

  # only metadata: anything starting with underscore
  _get_meta_attrs: ->
    _.filter @_attrs, (attr) -> _.startsWith _key(attr), '_'

  _filter_attrs: (options = {}) ->
    if options.omit_keys
      _.filter @_attrs, (attr) ->
        _key(attr) isnt options.omit_keys
    else
      @_attrs

  _friendly_sort = (attrs) ->
    attrs.sort _friendly_attr_order

  _friendly_attr_order = (attr1, attr2) ->
    key_sort_order = _friendly_item_order(_key(attr1), _key(attr2))
    if key_sort_order is 0
      value_sort_order = _friendly_item_order(_value(attr1), _value(attr2))
    key_sort_order or value_sort_order

  _friendly_item_order = (a, b) ->
    if type(a) is type(b) is 'string'
      if _.startsWith(a, '_') and not _.startsWith(b, '_')
        return -1
      else if not _.startsWith(a, '_') and _.startsWith(b, '_')
        return 1
      else if a.toLowerCase() < b.toLowerCase()
        return -1
      else if a.toLowerCase() > b.toLowerCase()
        return 1
      else
        return 0
    if a < b
      return -1
    else if a > b
      return 1
    else
      return 0

  _get_key: ->
    @get_keys()?[0]

  get_keys: ->
    @_get_meta KEY

  add_key: (key) ->
    @add_keys key

  add_keys: (key) ->
    @meta KEY, key

  has_key: (key) ->
    @_has_meta KEY, key

  _get_meta: (key) ->
    @get_values @_meta_ize key

  _has_meta: (search_key, search_value) ->
    @_has @_meta_ize(search_key), search_value

  get_values: (search_key) ->
    reduce @_attrs, @_accumulate_values, [], {search_key}

  _accumulate_values: (search_values, attr) ->
    if _key(attr) is @search_key
      search_values.push _value(attr)
    search_values

  _has: (search_key, search_value) ->
    if search_value?
      @_has_attr_key_and_value search_key, search_value
    else
      @_has_attr_key search_key

  _has_attr_key_and_value: (search_key, search_value) ->
    for attr in @_attrs
      if _key(attr) is search_key and _value(attr) is search_value
        return true
    return false

  _has_attr_key: (search_key) ->
    for attr in @_attrs
      if _key(attr) is search_key and _value(attr) is search_value
        return true
    return false

  _meta_ize: (key) ->
    if _.startsWith key, '_' then key else "_#{key}"

  ##################################################################################
  # Weights
  ##################################################################################

  weights: ->
    weights = {}
    for attr in @meta()
      @_add_data_weights weights, attr
    if @_numeric_props()
      for attr in @props()
        value = parseFloat _value(attr)
        if not Number.isNaN value
          weights[_key attr] ?= 0
          weights[_key attr] += value
    else
      for attr in @props()
        @_add_data_weights weights, attr
    weights

  _numeric_props: ->
    for attr in @props()  # check only props, which ignores metadata
      if Number.isNaN parseFloat _value attr
        return false
    return true

  _add_data_weights: (weights, attr) ->
    weights[_key attr] ?= 0             # keys are weighted = 0, values = 1
    weights[_value attr] ?= 0
    weights[_value attr] += 1

  ##################################################################################
  # Node attributes
  ##################################################################################

  _add_attr: (key, raw_value) ->
    unless type(key) is 'string'
      throw "Expected key to be of type 'string', got: '#{pjson key}'"
    value = if type(raw_value) in ['boolean', 'number', 'string']
      raw_value
    else if type(raw_value) in ['date']
      raw_value.toISOString()
    else if type(raw_value) in ['regexp', 'function']
      raw_value.toString()
    else if type(raw_value) in ['null', 'undefined']
      null
    else
      throw "Unexpected value '#{raw_value}' of type '#{type raw_value}' for key '#{key}'"
    attr = {}
    attr[key] = value
    @_attrs.push attr

  _key = (attr) ->
    _.first _.keys attr

  _value = (attr) ->
    _.first _.values attr

  ##################################################################################
  # Utilities
  ##################################################################################################

  @random_key = (key_length=88) ->
    alphabet = "123456789abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ".split /// ///   # base 58 -- no 0, O, 1, or l chars
    chars = for i in [0...key_length]
      alphabet[Math.floor Math.random() * 58]
    chars.join ''

module.exports = Node
