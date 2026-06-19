#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'saytime_weather/saytime_config'
require 'saytime_weather/ini'

class SaytimeConfigHarness
  include SaytimeWeather::SaytimeConfig

  attr_accessor :options, :config

  def initialize
    @options = { config_file: nil, use_gps: false, location_id: nil }
    @config = {}
  end

  def warn(*) = nil
end

def assert(condition, msg)
  raise msg unless condition
end

path = File.join(__dir__, 'fixtures', 'sample.ini')
h = SaytimeConfigHarness.new
h.options[:config_file] = path
h.load_config
assert(h.config['Temperature_mode'] == 'F', '-c should load Temperature_mode from custom ini')
assert(!h.gps_weather_enabled?, 'GPS not enabled without flag or location_source')

h2 = SaytimeConfigHarness.new
h2.config = { 'location_source' => 'gps' }
assert(h2.gps_weather_enabled?, 'location_source=gps enables GPS without -l')

h3 = SaytimeConfigHarness.new
h3.options[:use_gps] = true
h3.options[:location_id] = '77511'
assert(h3.gps_weather_enabled?, 'use_gps still true with -l (weather bridge clears location)')

puts 'saytime_config_test: ok'
