#!/usr/bin/env ruby
# frozen_string_literal: true

# saytime.rb - Time and weather announcement script (Ruby version)
# Copyright 2026 Jory A. Pratt, W5GLE
#
# - Announces current time (12-hour or 24-hour format)
# - Optionally announces weather conditions
# - Combines sound files and plays via Asterisk

_saytime_entry = File.realpath(__FILE__)
_saytime_root = File.dirname(_saytime_entry)
_package = File.directory?(File.join(_saytime_root, 'lib', 'saytime_weather')) ? _saytime_root : File.expand_path('../share/saytime-weather-rb', _saytime_root)
_lib = File.join(_package, 'lib')
$LOAD_PATH.unshift(_lib) unless $LOAD_PATH.include?(_lib)
require 'saytime_weather'
SaytimeWeather.root = _package

require 'time'

class SaytimeScript
  include SaytimeWeather::SaytimeLogging
  include SaytimeWeather::SaytimeConfig
  include SaytimeWeather::SaytimeCli
  include SaytimeWeather::SaytimePlayback
  include SaytimeWeather::SaytimeTime
  include SaytimeWeather::SaytimeWeatherBridge

  attr_reader :options, :config, :critical_error

  def initialize
    @options = {
      location_id: nil,
      node_number: nil,
      silent: 0,
      use_24hour: SaytimeWeather::SAYTIME_DEFAULT_24HOUR,
      verbose: SaytimeWeather::SAYTIME_DEFAULT_VERBOSE,
      dry_run: SaytimeWeather::SAYTIME_DEFAULT_DRY_RUN,
      test_mode: SaytimeWeather::SAYTIME_DEFAULT_TEST_MODE,
      weather_enabled: SaytimeWeather::SAYTIME_DEFAULT_WEATHER_ENABLED,
      greeting_enabled: SaytimeWeather::SAYTIME_DEFAULT_GREETING,
      custom_sound_dir: nil,
      log_file: nil,
      play_method: SaytimeWeather::SAYTIME_DEFAULT_PLAY_METHOD,
      default_country: nil
    }
    @config = {}
    @critical_error = false
    parse_options
    load_config
  end

  def run
    validate_options
    log_to_file('started')

    weather_sound_files = process_weather(@options[:location_id])

    now = get_current_time(@options[:location_id])

    time_sound_files = process_time(now, @options[:use_24hour])

    output_file = tmp_file('current-time.ulaw')
    final_sound_files = combine_sound_files(time_sound_files, weather_sound_files)

    if @options[:dry_run]
      info("Dry run mode - would play: #{final_sound_files}")
      exit 0
    end

    if final_sound_files && !final_sound_files.strip.empty?
      create_output_file(final_sound_files, output_file)
    end

    if @options[:silent] == 0
      play_announcement(@options[:node_number], output_file)
      cleanup_files(output_file, @options[:weather_enabled], @options[:silent])
    elsif [1, 2].include?(@options[:silent])
      info("Saved sound file to #{output_file}")
      cleanup_files(nil, @options[:weather_enabled], @options[:silent])
    end

    status = @critical_error ? 1 : 0
    log_to_file("finished exit=#{status}")
    exit status
  end
end

if __FILE__ == $PROGRAM_NAME
  script = SaytimeScript.new
  script.run
end
