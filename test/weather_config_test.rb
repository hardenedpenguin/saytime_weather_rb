#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'saytime_weather/config_error'
require 'saytime_weather/weather_config'
require 'saytime_weather/weather_helpers'
require 'saytime_weather/ini'

class WeatherConfigHarness
  include SaytimeWeather::WeatherConfig
  include SaytimeWeather::WeatherHelpers

  attr_accessor :options, :config, :provider_explicitly_set

  def initialize(config: {}, options: {})
    @config = config
    @options = { verbose: false }.merge(options)
    @provider_explicitly_set = true
  end

  def warn(*) = nil
end

def assert_raises(error_class, msg = nil)
  yield
  raise(msg || "expected #{error_class}")
rescue error_class
  nil
end

h = WeatherConfigHarness.new(
  config: { 'Temperature_mode' => 'F', 'weather_provider' => 'weatherapi' },
  options: {}
)
assert_raises(SaytimeWeather::ConfigError, 'weatherapi without key should raise') do
  h.validate_config
end

h2 = WeatherConfigHarness.new(
  config: { 'Temperature_mode' => 'X' },
  options: {}
)
assert_raises(SaytimeWeather::ConfigError, 'invalid temp mode should raise') do
  h2.validate_config
end

Dir.mktmpdir('cfg-missing') do |dir|
  missing = File.join(dir, 'nope.ini')
  h3 = WeatherConfigHarness.new(options: { config_file: missing })
  assert_raises(SaytimeWeather::ConfigError, 'missing custom config should raise') do
    h3.load_config
  end
end

puts 'weather_config_test: ok'
