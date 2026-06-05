#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'saytime_weather/weather_nws'

class NwsHarness
  include SaytimeWeather::WeatherNws
end

def assert_equal(expected, actual, msg = nil)
  return if expected == actual

  raise "#{msg || 'assertion'}: expected #{expected.inspect}, got #{actual.inspect}"
end

h = NwsHarness.new

assert_equal(true, h.nws_icon_night?('https://api.weather.gov/icons/land/night/few?size=medium'))
assert_equal(false, h.nws_icon_night?('https://api.weather.gov/icons/land/day/skc?size=medium'))

assert_equal('Partly Cloudy', h.apply_nws_night_condition('Mostly Sunny', 'https://api.weather.gov/icons/land/night/few'),
             'night icon should downgrade Mostly Sunny')
assert_equal('Mostly Sunny', h.apply_nws_night_condition('Mostly Sunny', 'https://api.weather.gov/icons/land/day/skc'),
             'day icon should leave Mostly Sunny')
assert_equal('Mainly Clear', h.apply_nws_night_condition('Sunny', nil, is_daytime: false))

puts 'nws_condition_test: ok'
