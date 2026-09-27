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

  # Optional weather fields: show_* = text output; announce_* = radio audio (all default NO).
  OPTIONAL_WEATHER_ANNOUNCE_FOR = {
    'show_precipitation' => 'announce_precipitation',
    'show_wind' => 'announce_wind',
    'show_pressure' => 'announce_pressure',
    'show_humidity' => 'announce_humidity',
    'show_feels_like' => 'announce_feels_like',
    'show_dewpoint' => 'announce_dewpoint',
    'show_uv' => 'announce_uv',
    'show_visibility' => 'announce_visibility'
  }.freeze

  OPTIONAL_WEATHER_DISPLAY_KEYS = OPTIONAL_WEATHER_ANNOUNCE_FOR.keys.freeze
  OPTIONAL_WEATHER_ANNOUNCE_KEYS = OPTIONAL_WEATHER_ANNOUNCE_FOR.values.freeze
end
