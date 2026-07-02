#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'saytime_weather/paths'
require 'saytime_weather/run_context'

def assert!(cond, msg)
  raise msg unless cond
end

Dir.mktmpdir do |tmpdir|
  prev = ENV['SAYTIME_TMP']
  ENV['SAYTIME_TMP'] = tmpdir

  legacy = File.join(tmpdir, 'temperature')
  File.write(legacy, '72')
  SaytimeWeather::RunContext.clear_legacy_scratch!
  assert!(!File.exist?(legacy), 'legacy temperature should be removed')

  SaytimeWeather::RunContext.begin_run!
  scoped = SaytimeWeather::RunContext.scoped_tmp_path('temperature')
  File.write(scoped, '55')
  saved = SaytimeWeather::RunContext.persistent_scratch_path('current-time.ulaw')
  File.write(saved, 'audio')

  SaytimeWeather::RunContext.cleanup!
  assert!(!File.exist?(scoped), 'scoped scratch should be cleaned up')
  assert!(File.exist?(saved), 'persistent save path must survive cleanup')

  SaytimeWeather::RunContext.clear_legacy_scratch!
  assert!(!File.exist?(saved), 'legacy clear removes fixed current-time.ulaw')

  File.write(saved, 'audio2')
  SaytimeWeather::RunContext.cleanup!(except: [saved])
  assert!(File.exist?(saved), 'cleanup except keeps explicit save path')

ensure
  if prev
    ENV['SAYTIME_TMP'] = prev
  else
    ENV.delete('SAYTIME_TMP')
  end
end

puts 'run_context_test: ok'
