#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'saytime_weather/weather_geocoding'
require 'saytime_weather/weather_airports'
require 'saytime_weather/weather_units'
require 'saytime_weather/weather_weatherapi'
require 'saytime_weather/endpoints'

class WeatherapiHarness
  include SaytimeWeather::WeatherGeocoding
  include SaytimeWeather::WeatherAirports
  include SaytimeWeather::WeatherUnits
  include SaytimeWeather::WeatherWeatherapi

  attr_accessor :config, :options

  def initialize(config = {})
    @config = {
      'default_country' => 'us',
      'show_precipitation' => 'YES',
      'show_wind' => 'YES',
      'show_pressure' => 'YES',
      'show_humidity' => 'YES'
    }.merge(config)
    @options = { verbose: false }
  end

  def warn(*) = nil
end

def assert_equal(expected, actual, msg = nil)
  return if expected == actual

  raise "#{msg || 'assertion'}: expected #{expected.inspect}, got #{actual.inspect}"
end

def assert(condition, msg)
  raise msg unless condition
end

fixture = JSON.parse(File.read(File.expand_path('fixtures/weatherapi_current.json', __dir__)))
h = WeatherapiHarness.new('weatherapi_key' => 'test-key')

parsed = h.parse_weatherapi_response(fixture)
assert(parsed, 'fixture should parse')
assert_equal(82.4, parsed[:temp])
assert_equal('Partly Cloudy', parsed[:condition])
assert_equal('America/Chicago', parsed[:timezone])
assert_equal('2026-05-19T14:30', parsed[:observation_time])
assert_equal(29.51, parsed[:lat])
assert_equal(-95.09, parsed[:lon])

night = fixture.dup
night['current']['is_day'] = 0
night['current']['condition']['text'] = 'Sunny'
night_parsed = h.parse_weatherapi_response(night)
assert_equal('Mainly Clear', night_parsed[:condition], 'is_day 0 should adjust Sunny for night')

assert_equal(nil, h.parse_weatherapi_response({ 'error' => { 'code' => 401 } }), 'API error should return nil')

url = SaytimeWeather::Endpoints.weatherapi_current_url('secret', '77511')
assert(url.include?('api.weatherapi.com'), 'weatherapi URL host')
assert(url.include?('q=77511'), 'weatherapi URL query')
assert(url.include?('key=secret'), 'weatherapi URL key param')

assert_equal('77511', h.weatherapi_query_for_location('77511'))
h.config['default_country'] = 'fr'
assert_equal('75001,FR', h.weatherapi_query_for_location('75001'))
h.config['default_country'] = 'au'
assert_equal('2000,AU', h.weatherapi_query_for_location('2000'))
assert_equal('iata:DFW', h.weatherapi_query_for_location('DFW'))
assert_equal('metar:KJFK', h.weatherapi_query_for_location('KJFK'))

prev = ENV['WEATHERAPI_KEY']
ENV.delete('WEATHERAPI_KEY')
ini_key = WeatherapiHarness.new('weatherapi_key' => ' ini-key ')
assert_equal('ini-key', ini_key.weatherapi_key, 'ini key should be used when set')

ENV['WEATHERAPI_KEY'] = 'env-key'
env_only = WeatherapiHarness.new
assert_equal('env-key', env_only.weatherapi_key)
ENV['WEATHERAPI_KEY'] = prev if prev
ENV.delete('WEATHERAPI_KEY') unless prev

puts 'weatherapi_test: ok'
