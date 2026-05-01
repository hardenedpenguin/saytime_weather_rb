# frozen_string_literal: true

module SaytimeWeather
  class << self
    attr_accessor :root
  end
end

require_relative 'saytime_weather/constants'
require_relative 'saytime_weather/ini'
require_relative 'saytime_weather/version'
require_relative 'saytime_weather/network'
require_relative 'saytime_weather/paths'
require_relative 'saytime_weather/endpoints'
require_relative 'saytime_weather/http_client'
require_relative 'saytime_weather/weather_helpers'
require_relative 'saytime_weather/weather_units'
require_relative 'saytime_weather/weather_config'
require_relative 'saytime_weather/weather_geocoding'
require_relative 'saytime_weather/weather_airports'
require_relative 'saytime_weather/weather_metar'
require_relative 'saytime_weather/weather_open_meteo'
require_relative 'saytime_weather/weather_nws'
require_relative 'saytime_weather/weather_metno'
require_relative 'saytime_weather/weather_wttr'
require_relative 'saytime_weather/weather_7timer'
require_relative 'saytime_weather/weather_sound'
require_relative 'saytime_weather/saytime_logging'
require_relative 'saytime_weather/saytime_config'
require_relative 'saytime_weather/saytime_cli'
require_relative 'saytime_weather/saytime_playback'
require_relative 'saytime_weather/saytime_time'
require_relative 'saytime_weather/saytime_weather_bridge'
