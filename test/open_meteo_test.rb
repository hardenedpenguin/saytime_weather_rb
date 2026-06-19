#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'saytime_weather/weather_open_meteo'

class OpenMeteoHarness
  include SaytimeWeather::WeatherOpenMeteo
end

def assert_equal(expected, actual, msg = nil)
  return if expected == actual

  raise "#{msg || 'assertion'}: expected #{expected.inspect}, got #{actual.inspect}"
end

h = OpenMeteoHarness.new

assert_equal(0, h.open_meteo_is_day(0), 'is_day 0 must stay 0')
assert_equal(0, h.open_meteo_is_day('0'), 'is_day string 0 must stay 0')
assert_equal(1, h.open_meteo_is_day(1), 'is_day 1 must stay 1')
assert_equal(1, h.open_meteo_is_day('1'), 'is_day string 1 must stay 1')
assert_equal(1, h.open_meteo_is_day(nil), 'missing is_day defaults to 1')

assert_equal('Mainly Clear', h.weather_code_to_text(1, 0), 'night code 1')
assert_equal('Sunny', h.weather_code_to_text(1, 1, local_time: '2026-05-30T14:00'), 'afternoon code 1')
assert_equal('Partly Cloudy', h.weather_code_to_text(2, 1, local_time: '2026-05-30T21:30'),
             'evening code 2 should not be Mostly Sunny')
assert_equal('Mostly Sunny', h.weather_code_to_text(2, 1, local_time: '2026-05-30T15:00'),
             'afternoon code 2')

json = {
  'current' => {
    'temperature_2m' => 28.7,
    'weather_code' => 2,
    'is_day' => 0,
    'time' => '2026-05-30T21:30'
  },
  'timezone' => 'Europe/Paris'
}
parsed = h.parse_openmeteo_response(json)
assert_equal('Partly Cloudy', parsed[:condition], 'is_day 0 must not become Sunny via || 1')
assert_equal('2026-05-30T21:30', parsed[:observation_time])

puts 'open_meteo_test: ok'
