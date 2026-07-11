#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'saytime_weather/weather_conditions'
require 'saytime_weather/ini'
require 'saytime_weather/weather_units'

class TestRunner
  def self.run
    t = new
    t.test_weather_conditions_metar_light_rain
    t.test_weather_conditions_from_text
    t.test_weather_conditions_metno
    t.test_ini_parse
    t.test_units
    load File.expand_path('provider_order_test.rb', __dir__)
    load File.expand_path('cache_test.rb', __dir__)
    load File.expand_path('saytime_time_test.rb', __dir__)
    load File.expand_path('saytime_regression_audit.rb', __dir__)
    load File.expand_path('gps_test.rb', __dir__)
    load File.expand_path('geocoding_config_test.rb', __dir__)
    load File.expand_path('open_meteo_test.rb', __dir__)
    load File.expand_path('weatherapi_test.rb', __dir__)
    load File.expand_path('weather_sound_test.rb', __dir__)
    load File.expand_path('weather_config_test.rb', __dir__)
    load File.expand_path('saytime_cli_test.rb', __dir__)
    load File.expand_path('weather_gps_run_test.rb', __dir__)
    load File.expand_path('nws_condition_test.rb', __dir__)
    load File.expand_path('weather_numeric_test.rb', __dir__)
    load File.expand_path('saytime_config_test.rb', __dir__)
    load File.expand_path('weather_entry_test.rb', __dir__)
    load File.expand_path('run_context_test.rb', __dir__)
    puts "All #{@count} tests passed."
  end

  def initialize
    @count = 0
  end

  def assert_equal(expected, actual, msg = nil)
    @count += 1
    return if expected == actual

    raise "#{msg || 'assertion'}: expected #{expected.inspect}, got #{actual.inspect}"
  end

  def test_weather_conditions_metar_light_rain
    metar = 'KJFK 251756Z 28015KT 5SM -RA FEW020 BKN040 12/10 A3012'
    assert_equal('Light Rain', SaytimeWeather::WeatherConditions.from_metar(metar))
  end

  def test_weather_conditions_from_text
    assert_equal('Partly Cloudy', SaytimeWeather::WeatherConditions.from_text('Partly cloudy'))
    assert_equal('Partly Cloudy', SaytimeWeather::WeatherConditions.from_text('Mostly Clear'),
                 'NWS night text must not become Mostly Sunny')
    assert_equal('Mostly Sunny', SaytimeWeather::WeatherConditions.from_text('Mostly Sunny'))
    assert_equal('Partly Cloudy', SaytimeWeather::WeatherConditions.adjust_for_night('Mostly Sunny'))
    assert_equal('Mainly Clear', SaytimeWeather::WeatherConditions.adjust_for_night('Sunny'))
    assert_equal(nil, SaytimeWeather::WeatherConditions.from_text('xyzzy unknown phrase'),
                 'unknown text should not default to Clear')
    assert_equal('Thunderstorm', SaytimeWeather::WeatherConditions.from_text('Heavy thunderstorm'))
  end

  def test_weather_conditions_metno
    assert_equal('Rain', SaytimeWeather::WeatherConditions.from_metno_symbol('rain'))
    assert_equal('Clear', SaytimeWeather::WeatherConditions.from_metno_symbol('clearsky_day'))
  end

  def test_ini_parse
    path = File.join(__dir__, 'fixtures', 'sample.ini')
    ini = SaytimeWeather::Ini.parse_file(path)
    assert_equal('F', ini['weather']['Temperature_mode'])
    assert_equal('openmeteo', ini['weather']['weather_provider'])
  end

  def test_units
    mod = Object.new.extend(SaytimeWeather::WeatherUnits)
    assert_equal(32, mod.ms_to_mph(14.3))
    assert_equal(1.0, mod.mm_to_inches(25.4))
    assert_equal('NE', mod.wind_direction_to_cardinal(45))
    mph_ms = mod.mph_to_ms(22.3694)
    assert_equal(true, (mph_ms - 10.0).abs < 0.01, "mph_to_ms expected ~10, got #{mph_ms}")
  end
end

TestRunner.run if __FILE__ == $PROGRAM_NAME
