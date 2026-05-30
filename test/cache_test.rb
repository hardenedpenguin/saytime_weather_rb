#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'saytime_weather/cache'
require 'saytime_weather/paths'

path = File.join(SaytimeWeather::Paths.tmp_dir, 'saytime-test-cache.json')
File.unlink(path) if File.exist?(path)

SaytimeWeather::Cache.write_json(path, { 'timezone' => 'Europe/Berlin' })
data = SaytimeWeather::Cache.read_json(path, 3600)
raise 'cache read failed' unless data && data['timezone'] == 'Europe/Berlin'

File.unlink(path)
puts 'cache_test: ok'
