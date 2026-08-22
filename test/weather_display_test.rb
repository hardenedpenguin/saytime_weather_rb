#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'saytime_weather'

def assert(condition, msg)
  raise msg unless condition
end

def assert_equal(expected, actual, msg = nil)
  return if expected == actual

  raise "#{msg || 'assertion'}: expected #{expected.inspect}, got #{actual.inspect}"
end

def assert_includes(haystack, needle, msg = nil)
  assert(haystack.include?(needle), msg || "expected #{needle.inspect} in #{haystack.inspect}")
end

class NwsFeelsHarness
  include SaytimeWeather::WeatherNws
  include SaytimeWeather::WeatherUnits
end

h = NwsFeelsHarness.new
hi_f = h.celsius_to_fahrenheit(35.0)
assert_equal(hi_f, h.nws_feels_like_fahrenheit('heatIndex' => { 'value' => 35.0 }),
             'heatIndex should convert to Fahrenheit')
wc_f = h.celsius_to_fahrenheit(-5.0)
assert_equal(wc_f, h.nws_feels_like_fahrenheit('windChill' => { 'value' => -5.0 }),
             'windChill should convert when heatIndex absent')
assert_equal(hi_f, h.nws_feels_like_fahrenheit(
               'heatIndex' => { 'value' => 35.0 },
               'windChill' => { 'value' => -5.0 }
             ), 'heatIndex takes precedence over windChill')

class OpenMeteoParamsHarness
  include SaytimeWeather::WeatherOpenMeteo

  attr_accessor :config

  def initialize(config)
    @config = config
  end
end

om = OpenMeteoParamsHarness.new(
  'show_feels_like' => 'YES',
  'show_dewpoint' => 'YES',
  'show_uv' => 'YES',
  'show_visibility' => 'YES'
)
params = om.open_meteo_current_params(include_extras: true)
assert_includes(params, 'apparent_temperature')
assert_includes(params, 'dew_point_2m')
assert_includes(params, 'uv_index')
assert_includes(params, 'visibility')

Dir.mktmpdir do |dir|
  ini = File.join(dir, 'weather.ini')
  File.write(ini, <<~INI)
    [weather]
    Temperature_mode = F
    weather_provider = openmeteo
    weather_provider_random = NO
    show_feels_like = YES
    show_dewpoint = YES
    show_uv = YES
    show_visibility = YES
  INI

  script = SaytimeWeather::WeatherScript.new(options: { config_file: ini })
  script.instance_variable_set(:@weather_data, {
                                 feels_like: 88.0,
                                 dewpoint: 62.0,
                                 uv_index: 7.2,
                                 visibility_m: 16_093.44
                               })
  out = script.send(:build_output_line, 75, 24, 'Clear')
  assert_includes(out, 'Feels like 88°F')
  assert_includes(out, 'Dewpoint 62°F')
  assert_includes(out, 'UV 7')
  assert_includes(out, 'Visibility 10.0 mi')
  assert(out.start_with?('75°F, 24°C /'), 'line should start with temperature')
  assert_includes(out, 'Clear')
end

Dir.mktmpdir do |dir|
  ini = File.join(dir, 'weather.ini')
  File.write(ini, <<~INI)
    [weather]
    Temperature_mode = F
    weather_provider = openmeteo
    weather_provider_random = NO
    show_visibility = YES
  INI

  script = SaytimeWeather::WeatherScript.new(options: { config_file: ini })
  script.instance_variable_set(:@weather_data, { visibility_m: 0 })
  out = script.send(:build_output_line, 75, 24, 'Foggy')
  assert_includes(out, 'Visibility 0.0 mi', 'zero visibility should be shown')
end

puts 'weather_display_test: ok'
