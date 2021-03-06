{Promise} = require 'q'
fs = require 'fs'
mime = require 'mime'
oauth = require 'oauth'
request = require 'request'
wsse = require 'wsse'
xml2js = require 'xml2js'

# Hatena::Fotolife API wrapper
#
# - POST   PostURI (/atom/post)                => Fotolife#create
# - PUT    EditURI (/atom/edit/XXXXXXXXXXXXXX) => Fotolife#update
# - DELETE EditURI (/atom/edit/XXXXXXXXXXXXXX) => Fotolife#destroy
# - GET    EditURI (/atom/edit/XXXXXXXXXXXXXX) => Fotolife#show
# - GET    FeedURI (/atom/feed)                => Fotolife#index
class Fotolife

  @BASE_URL = 'http://f.hatena.ne.jp'

  # constructor
  # params:
  #   options: (required)
  #   - type     : authentication type. default `'wsse'`
  #   (type 'wsse')
  #   - username : wsse authentication username. (required)
  #   - apikey   : wsse authentication apikey. (required)
  #   (type 'oauth')
  #   - consumerKey       : oauth consumer key. (required)
  #   - consumerSecret    : oauth consumer secret. (required)
  #   - accessToken       : oauth access token. (required)
  #   - accessTokenSecret : oauth access token secret. (required)
  constructor: ({
    type,
    username,
    apikey,
    consumerKey
    consumerSecret,
    accessToken,
    accessTokenSecret
  }) ->
    @_type = type ? 'wsse'
    @_username = username
    @_apikey = apikey
    @_consumerKey = consumerKey
    @_consumerSecret = consumerSecret
    @_accessToken = accessToken
    @_accessTokenSecret = accessTokenSecret

  # POST PostURI (/atom/post)
  # params:
  #   options: (required)
  #   - file     : 'content'. image file path. (required)
  #   - title    : 'title'. image title. default `''`.
  #   - type     : 'type'. content-type. default `mime.lookup(file)`.
  #   - folder   : 'dc:subject'. folder name. default `undefined`.
  #   - generator: 'generator'. tool name. default `undefined`.
  #   callback:
  #   - err: error
  #   - res: response
  # returns:
  #   Promise
  create: ({ file, title, type, folder, generator }, callback) ->
    return @_reject('options.file is required', callback) unless file?
    unless fs.existsSync(file)
      return @_reject('options.file does not exist', callback)
    title = title ? ''
    type = type ? mime.lookup(file)
    encoded = fs.readFileSync(file).toString('base64')
    method = 'post'
    path = '/atom/post'
    body = entry:
      $:
        xmlns: 'http://purl.org/atom/ns#'
      title:
        _: title
      content:
        $:
          mode: 'base64'
          type: type
        _: encoded
    body.entry['dc:subject'] = { _: folder } if folder?
    body.entry.generator = { _: generator } if generator?
    statusCode = 201
    @_request { method, path, body, statusCode }, callback

  # PUT EditURI (/atom/edit/XXXXXXXXXXXXXX)
  # params:
  #   options: (required)
  #   - id    : image id. (required)
  #   - title : 'title'. image title. (required)
  #   callback:
  #   - err: error
  #   - res: feed
  # returns:
  #   Promise
  update: ({ id, title }, callback) ->
    return @_reject('options.id is required', callback) unless id?
    return @_reject('options.title is required', callback) unless title?
    method = 'put'
    path = '/atom/edit/' + id
    body =
      entry:
        $:
          xmlns: 'http://purl.org/atom/ns#'
        title:
          _: title
    statusCode = 200
    @_request { method, path, body, statusCode }, callback

  # DELETE EditURI (/atom/edit/XXXXXXXXXXXXXX)
  # params:
  #   options: (required)
  #   - id: image id. (required)
  #   callback:
  #   - err: error
  #   - res: response
  # returns:
  #   Promise
  destroy: ({ id }, callback) ->
    return @_reject('options.id is required', callback) unless id?
    method = 'delete'
    path = '/atom/edit/' + id
    statusCode = 200
    @_request { method, path, statusCode }, callback

  # GET EditURI (/atom/edit/XXXXXXXXXXXXXX)
  # params:
  #   options: (required)
  #   - id: image id. (required)
  #   callback:
  #   - err: error
  #   - res: response
  # returns:
  #   Promise
  show: ({ id }, callback) ->
    return @_reject('options.id is required', callback) unless id?
    method = 'get'
    path = '/atom/edit/' + id
    statusCode = 200
    @_request { method, path, statusCode }, callback

  # GET FeedURI (/atom/feed)
  # params:
  #   options:
  #   callback:
  #   - err: error
  #   - res: response
  # returns:
  #   Promise
  index: (options, callback) ->
    callback = options unless callback?
    method = 'get'
    path = '/atom/feed'
    statusCode = 200
    @_request { method, path, statusCode }, callback

  _reject: (message, callback) ->
    try
      e = new Error(message)
      callback(e) if callback?
      Promise.reject(e)
    catch
      Promise.reject(e)

  _request: ({ method, path, body, statusCode }, callback) ->
    callback = callback ? (->)
    params = {}
    params.method = method
    params.url = Fotolife.BASE_URL + path
    if @_type is 'oauth'
      params.oauth =
        consumer_key: @_consumerKey
        consumer_secret: @_consumerSecret
        token: @_accessToken
        token_secret: @_accessTokenSecret
    else # @_type is 'wsse'
      token = wsse().getUsernameToken @_username, @_apikey, nonceBase64: true
      params.headers =
        'Authorization': 'WSSE profile="UsernameToken"'
        'X-WSSE': 'UsernameToken ' + token
    promise = if body? then @_toXml(body) else Promise.resolve(null)
    promise
      .then (body) =>
        params.body = body if body?
        @_requestPromise params
      .then (res) =>
        if res.statusCode isnt statusCode
          throw new Error("HTTP status code is #{res.statusCode}")
        @_toJson res.body
      .then (json) ->
        callback(null, json)
        json
      .then null, (err) ->
        callback(err)
        throw err

  _requestPromise: (params) ->
    new Promise (resolve, reject) =>
      @_rawRequest params, (err, res) ->
        if err?
          reject err
        else
          resolve res

  _toJson: (xml) ->
    new Promise (resolve, reject) ->
      parser = new xml2js.Parser explicitArray: false, explicitCharkey: true
      parser.parseString xml, (err, result) ->
        if err?
          reject err
        else
          resolve result

  _toXml: (json) ->
    builder = new xml2js.Builder()
    try
      xml = builder.buildObject json
      Promise.resolve xml
    catch e
      Promise.reject e

  _rawRequest: request

  _mime: mime

module.exports = Fotolife
