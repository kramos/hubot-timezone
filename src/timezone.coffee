# Description:
#   Enable hubot to convert timezones for you.
#
# Dependencies:
#   "moment": "^2.10.3"
#
# Configuration:
#   HUBOT_SHRDSVS_LOCATIONS
#
# Commands:
#   hubot time in <location> - Ask hubot for a time in a location
#   hubot <time> in <location> - Convert a given time to a given location, e.g. "1pm in Sydney"
#   hubot <time> from <location> to <location> - Convert a given time between 2 locations
#   hubot shared services/dcsc/pcsc time - The current time in all locations
#   hubot shared services/dcsc/pcsc at <time> - The time in all locations at the stated UK time
#
# Notes:
#   The timezone the hubot server's timezone.
#   The Shared Service team locations should be stored in HUBOT_SHRDSVS_LOCATIONS in CSV format

querystring = require('querystring')
moment = require('moment')

parseTime = (timeStr) ->
  m = moment.utc(timeStr, [
    'ha', 'h:ma',
    'YYYY-M-D ha', 'YYYY-M-D h:ma',
    'YYYY-D-M ha', 'YYYY-D-M h:ma',
    'M-D-YYYY ha', 'M-D-YYYY h:ma',
    'D-M-YYYY ha', 'D-M-YYYY h:ma'
  ], true)
  return if m.isValid() then m.unix() else null

formatTime = (timestamp) ->
  return moment.utc(timestamp).format('h:mm:ss a, dddd')

# Use Google's Geocode and Timezone APIs to get timezone offset for a location.
getTimezoneInfo = (res, timestamp, location, callback) ->
  q = querystring.stringify({ address: location, sensor: false })

  res.http('https://maps.googleapis.com/maps/api/geocode/json?' + q)
    .get() (err, httpRes, body) ->
      if err
        callback(err, null)
        return

      json = JSON.parse(body)
      if json.results.length == 0
        callback(new Error('no address found'), null)
        return

      latlong = json.results[0].geometry.location
      formattedAddress = json.results[0].formatted_address
      tzq = querystring.stringify({
        location: latlong.lat + ',' + latlong.lng,
        timestamp: timestamp,
        sensor: false
      })

      res.http('https://maps.googleapis.com/maps/api/timezone/json?' + tzq)
        .get() (err, httpRes, body) ->
          if err
            callback(err, null)
            return

          json = JSON.parse(body)
          if json.status != 'OK'
            callback(new Error('no timezone found'))
            return

          callback(null, {
            formattedAddress: formattedAddress,
            dstOffset: json.dstOffset,
            rawOffset: json.rawOffset
          })

# Convert time between 2 locations and send back the results.
# If `fromLocation` is null, send back time in `toLocation`.
convertTime = (res, timestamp, fromLocation, toLocation, verbose) ->
  sendLocalTime = (utcTimestamp, location) ->
    getTimezoneInfo res, utcTimestamp, location, (err, result) ->
      if (err)
        res.send("I can't find the time at #{location}.")
      else
        localTimestamp = (utcTimestamp + result.dstOffset + result.rawOffset) * 1000
        if typeof verbose != 'undefined'
          res.send("Time in #{result.formattedAddress} is #{formatTime(localTimestamp)}")
        else
          res.send(formatTime(localTimestamp))

  if fromLocation
    getTimezoneInfo res, timestamp, fromLocation, (err, result) ->
      if (err)
        res.send("I can't find the time at #{fromLocation}.")
      else
        utcTimestamp = timestamp - result.dstOffset - result.rawOffset
        sendLocalTime(utcTimestamp, toLocation)
  else
    sendLocalTime(timestamp, toLocation)

module.exports = (robot) ->

  robot.respond /(.*) from (.*) to (.*)/i, (res) ->
    timestamp = parseTime(res.match[1])
    return unless timestamp
    convertTime(res, timestamp, res.match[2], res.match[3])

  robot.respond /(.*) in (.*)/i, (res) ->
    requestedTime = res.match[1]
    defaultOffset = robot.brain.data.timezoneOffset || moment().utcOffset()
    if requestedTime.toLowerCase() == 'time'
      timestamp = moment().unix()
    else if parseTime(requestedTime)
      timestamp = parseTime(requestedTime) - defaultOffset * 60
    else
      return
    convertTime(res, timestamp, null, res.match[2])

  robot.respond /(Shared Services?|dcs.?|pcs.?) time *(at)? *(.*)/i, (res) ->
    requestedTime = if res.match[3] == '' then moment().unix() else parseTime(res.match[3])
    shrdsvc_locations = process.env.HUBOT_SHRDSVS_LOCATIONS
    if typeof shrdsvc_locations == 'undefined'
      res.send "The Shared Service team locations should be stored on the server an env variable: HUBOT_SHRDSVS_LOCATIONS in (CSV format)."
    else
      for location in shrdsvc_locations.split(',')
        convertTime(res, requestedTime, null, location, 'verbose')

  robot.respond /(Shared Services?|dcs.?|pcs.?) locations?/i, (res) ->
    shrdsvc_locations = process.env.HUBOT_SHRDSVS_LOCATIONS
    res.send "As per env var: HUBOT_SHRDSVS_LOCATIONS, " + shrdsvc_locations

