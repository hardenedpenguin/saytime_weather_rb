# frozen_string_literal: true

module SaytimeWeather
  # Buffer for concatenating .ulaw sound files (weather condition stitch + saytime output)
  HTTP_BUFFER_SIZE = 8192

  SAYTIME_DEFAULT_VERBOSE = false
  SAYTIME_DEFAULT_DRY_RUN = false
  SAYTIME_DEFAULT_TEST_MODE = false
  SAYTIME_DEFAULT_WEATHER_ENABLED = true
  SAYTIME_DEFAULT_24HOUR = false
  SAYTIME_DEFAULT_GREETING = true
  SAYTIME_DEFAULT_PLAY_METHOD = 'localplay'
  SAYTIME_PLAY_DELAY = 5
end
