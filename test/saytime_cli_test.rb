#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'saytime_weather/version'
require 'saytime_weather/saytime_cli'

class SaytimeCliHarness
  include SaytimeWeather::SaytimeCli

  def initialize
    @options = {
      play_method: 'localplay',
      node_number: nil,
      silent: 0,
      use_24hour: false,
      verbose: false,
      dry_run: false,
      test_mode: false,
      weather_enabled: false,
      greeting_enabled: true,
      custom_sound_dir: nil,
      log_file: nil,
      default_country: nil,
      config_file: nil,
      weather_subprocess: false,
      use_gps: false,
      location_id: nil
    }
  end

  def error(*) = nil
  def show_usage = nil
  def gps_weather_enabled? = false
end

def assert_equal(expected, actual, msg = nil)
  return if expected == actual

  raise "#{msg || 'assertion'}: expected #{expected.inspect}, got #{actual.inspect}"
end

h = SaytimeCliHarness.new

[
  [%w[-m -n 546052], 'playback'],
  [%w[-m -u -n 546052], 'playback'],
  [%w[-mu -n 546052], 'playback'],
  [%w[-um -n 546052], 'playback'],
  [%w[-n 546052 -m], 'playback'],
  [%w[-m playback -n 546052], 'playback'],
  [%w[-m localplay -n 546052], 'localplay'],
  [%w[-n 546052], 'localplay'],
  [%w[-n546052], 'localplay', '546052']
].each do |argv, expected_method, expected_node|
  ARGV.replace(argv.dup)
  h.parse_options
  assert_equal(expected_method, h.instance_variable_get(:@options)[:play_method], "play_method for #{argv.inspect}")
  expected_node ||= '546052'
  assert_equal(expected_node, h.instance_variable_get(:@options)[:node_number], "node for #{argv.inspect}")
  assert_equal(true, h.instance_variable_get(:@options)[:use_24hour], "24h for #{argv.inspect}") if argv.include?('-u') || argv.any? { |a| a == '-mu' || a == '-um' }
end

ARGV.replace(%w[-mu -n 546052])
h.parse_options
assert_equal(true, h.instance_variable_get(:@options)[:use_24hour], '-mu should enable 24-hour')

puts 'saytime_cli_test: ok'
