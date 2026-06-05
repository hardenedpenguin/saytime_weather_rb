#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'saytime_weather'

class GpsWeatherRunHarness < SaytimeWeather::WeatherScript
  def fetch_weather_for_location(_location)
    ['72', 'Clear', 'test']
  end

  def write_temperature_file(*) = true
  def process_weather_condition(*) = true
  def cleanup_old_files = nil
  def error(*) = nil
end

def assert(condition, msg)
  raise msg unless condition
end

script = GpsWeatherRunHarness.new(options: { use_gps: true })
assert(script.run(location: nil) == true, 'GPS run with nil location should succeed when weather fetch works')

puts 'weather_gps_run_test: ok'
