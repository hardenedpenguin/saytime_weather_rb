#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'fileutils'
require 'saytime_weather/run_context'
require 'saytime_weather/weather_sound'
require 'saytime_weather/weather_helpers'

class WeatherSoundHarness
  include SaytimeWeather::WeatherHelpers
  include SaytimeWeather::WeatherSound

  attr_accessor :options, :config

  def initialize(custom_dir: nil)
    @options = { verbose: true, custom_sound_dir: custom_dir }
    @config = { 'process_condition' => 'YES' }
    SaytimeWeather::RunContext.begin_run!
  end

  def warn(msg, critical = false)
    @warnings ||= []
    @warnings << msg if critical || @options[:verbose]
  end
end

def assert!(cond, msg)
  raise msg unless cond
end

Dir.mktmpdir('wx-sound-test') do |root|
  default_wx = File.join(root, 'default', 'wx')
  custom_wx = File.join(root, 'custom', 'wx')
  FileUtils.mkdir_p(default_wx)
  FileUtils.mkdir_p(custom_wx)
  File.write(File.join(default_wx, 'light-rain.ulaw'), 'RAIN')
  File.write(File.join(custom_wx, 'light-rain.ulaw'), 'RAIN')

  h = WeatherSoundHarness.new(custom_dir: File.join(root, 'default'))
  h.process_weather_condition('Light Rain')
  path = SaytimeWeather::RunContext.scoped_tmp_path('condition.ulaw')
  assert!(File.exist?(path), 'default wx should build condition when file exists')
  assert!(File.read(path) == 'RAIN', 'default wx/light-rain.ulaw should be used')
  SaytimeWeather::RunContext.cleanup!

  h2 = WeatherSoundHarness.new(custom_dir: File.join(root, 'custom'))
  SaytimeWeather::RunContext.begin_run!
  h2.process_weather_condition('Light Rain')
  path = SaytimeWeather::RunContext.scoped_tmp_path('condition.ulaw')
  assert!(File.exist?(path), 'custom wx dir should produce condition.ulaw')
  assert!(File.read(path) == 'RAIN', 'custom wx/light-rain.ulaw should be used')
  SaytimeWeather::RunContext.cleanup!

  h3 = WeatherSoundHarness.new(custom_dir: File.join(root, 'custom'))
  SaytimeWeather::RunContext.begin_run!
  h3.process_weather_condition('Torrential Hail')
  path3 = SaytimeWeather::RunContext.scoped_tmp_path('condition.ulaw')
  assert!(!File.exist?(path3), 'no match must not write condition.ulaw')
  assert!(h3.instance_variable_get(:@warnings)&.any? { |w| w.include?('No weather condition sound') },
          'should warn when no condition audio')
  assert!(!File.exist?(File.join(custom_wx, 'clear.ulaw')), 'must not fall back to clear.ulaw')
  SaytimeWeather::RunContext.cleanup!
end

puts 'weather_sound_test: ok'
