#!/usr/bin/env ruby
# frozen_string_literal: true

# weather.rb - Weather retrieval script for saytime-weather (Ruby version)
# Copyright 2026 Jory A. Pratt, W5GLE

_weather_entry = File.realpath(__FILE__)
_weather_root = File.dirname(_weather_entry)
_package = File.directory?(File.join(_weather_root, 'lib', 'saytime_weather')) ? _weather_root : File.expand_path('../share/saytime-weather-rb', _weather_root)
_lib = File.join(_package, 'lib')
$LOAD_PATH.unshift(_lib) unless $LOAD_PATH.include?(_lib)
require 'saytime_weather/weather_entry'
SaytimeWeather.root = _package

if __FILE__ == $PROGRAM_NAME
  result = SaytimeWeather::WeatherScript.new.run
  exit(result == :usage ? 0 : (result ? 0 : 1))
end
