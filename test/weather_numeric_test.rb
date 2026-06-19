#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'saytime_weather/weather_numeric'

def assert(condition, msg)
  raise msg unless condition
end

assert(SaytimeWeather::WeatherNumeric.numeric_temp?(0), '0°F is a valid temperature')
assert(SaytimeWeather::WeatherNumeric.numeric_temp?(-9), '-9°F is valid')
assert(!SaytimeWeather::WeatherNumeric.numeric_temp?(nil), 'nil is not valid temp')

assert(SaytimeWeather::WeatherNumeric.valid_weather_data?({ temp: 0, condition: 'Clear' }),
       '0°F with condition is valid weather data')
assert(!SaytimeWeather::WeatherNumeric.valid_weather_data?({ temp: nil, condition: 'Clear' }),
       'missing temp is invalid')
assert(!SaytimeWeather::WeatherNumeric.valid_weather_data?({ temp: 72, condition: '' }),
       'empty condition is invalid')

puts 'weather_numeric_test: ok'
