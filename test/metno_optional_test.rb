#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'saytime_weather/weather_metno'

class MetnoOptionalHarness
  include SaytimeWeather::WeatherOptionalFields
  include SaytimeWeather::WeatherMetNo
  include SaytimeWeather::WeatherUnits

  attr_accessor :config, :options

  def initialize(config)
    @config = config
    @options = { verbose: false }
  end

  def safe_decode_json(_) = nil
end

def assert(condition, msg)
  raise msg unless condition
end

h = MetnoOptionalHarness.new('show_wind' => 'NO', 'announce_wind' => 'YES')
assert(h.optional_weather_field_enabled?('show_wind'), 'announce_wind should enable wind fetch flag')

h2 = MetnoOptionalHarness.new('show_wind' => 'NO', 'announce_wind' => 'NO')
assert(!h2.optional_weather_field_enabled?('show_wind'), 'wind fetch flag off when both disabled')

puts 'metno_optional_test: ok'
