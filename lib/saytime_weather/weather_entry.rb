# frozen_string_literal: true

# Minimal load path for weather.rb (avoids loading saytime modules).
module SaytimeWeather
  class << self
    attr_accessor :root
  end
end

require_relative 'constants'
require_relative 'ini'
require_relative 'version'
require_relative 'network'
require_relative 'paths'
require_relative 'endpoints'
require_relative 'http_client'
require_relative 'weather_conditions'
require_relative 'weather_helpers'
require_relative 'weather_units'
require_relative 'weather_config'
require_relative 'weather_geocoding'
require_relative 'weather_airports'
require_relative 'weather_metar'
require_relative 'weather_open_meteo'
require_relative 'weather_nws'
require_relative 'weather_metno'
require_relative 'weather_wttr'
require_relative 'weather_7timer'
require_relative 'weather_sound'
require_relative 'weather_script'
require_relative 'weather_runner'
