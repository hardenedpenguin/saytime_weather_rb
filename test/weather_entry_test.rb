#!/usr/bin/env ruby
# frozen_string_literal: true

# Standalone weather.rb loads weather_entry.rb (not saytime_weather.rb).
# RunContext must be available on that path (0.0.27 regression).
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'saytime_weather/weather_entry'

def assert(condition, msg)
  raise msg unless condition
end

assert(SaytimeWeather::RunContext.respond_to?(:ensure_run!),
       'weather_entry must load RunContext for standalone weather.rb')
assert(SaytimeWeather::WeatherNumeric.respond_to?(:numeric_temp?),
       'weather_entry must load WeatherNumeric')

SaytimeWeather::RunContext.begin_run!
path = SaytimeWeather::RunContext.scoped_tmp_path('temperature')
assert(path.include?('temperature.'), "scoped path should include run id (#{path})")
SaytimeWeather::RunContext.cleanup!

puts 'weather_entry_test: ok'
