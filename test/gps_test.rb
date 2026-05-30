#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'time'
require 'saytime_weather/weather_geocoding'
require 'saytime_weather/gps'
require 'saytime_weather/cache'
require 'saytime_weather/paths'

class GpsHarness
  include SaytimeWeather::WeatherGeocoding
  include SaytimeWeather::WeatherGps

  attr_accessor :config, :options

  def initialize(config = {}, options = {})
    @config = config
    @options = options
    @explicit_location = options[:explicit_location]
  end

  def warn(*) = nil
end

def assert(condition, msg)
  raise msg unless condition
end

h = GpsHarness.new({}, { use_gps: true })
assert(h.gps_location_enabled?, '--gps option should enable GPS')

h2 = GpsHarness.new({ 'location_source' => 'gps' }, {})
assert(h2.gps_location_enabled?, 'location_source=gps should enable GPS')

h3 = GpsHarness.new({ 'location_source' => 'gps' }, { explicit_location: true })
assert(!h3.gps_location_enabled?, 'explicit location should override location_source=gps')

coords = h.parse_coordinate_literal('48.8566, 2.3522')
assert(coords == [48.8566, 2.3522], 'coordinate literal parse')

assert(!h.parse_coordinate_literal('75001'), 'postal should not parse as coordinates')

tpv = {
  'class' => 'TPV',
  'mode' => 3,
  'lat' => 48.8566,
  'lon' => 2.3522,
  'time' => Time.now.utc.iso8601
}
fix = h.send(:extract_fix, tpv)
assert(fix[:lat] == 48.8566, 'coordinate rounding to 4 decimals')
assert(h.send(:valid_tpv?, tpv, 2, 300), 'valid TPV should pass')

bad = tpv.merge('mode' => 1)
assert(!h.send(:valid_tpv?, bad, 2, 300), 'mode below minimum should fail')

cache_path = SaytimeWeather::Paths.gps_fix_cache_path
File.unlink(cache_path) if File.exist?(cache_path)
h.send(:write_gps_fix_cache, fix)
cached = h.send(:read_gps_fix_cache)
assert(cached && cached[:lat] == fix[:lat], 'GPS fix cache round trip')
File.unlink(cache_path)

puts 'gps_test: ok'
