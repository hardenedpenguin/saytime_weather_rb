#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'saytime_weather/saytime_playback'
require 'saytime_weather/saytime_time'
require 'saytime_weather/paths'

class SaytimeTimeHarness
  include SaytimeWeather::SaytimePlayback
  include SaytimeWeather::SaytimeTime

  def initialize
    @options = {}
  end
end

def assert(condition, msg)
  raise msg unless condition
end

h = SaytimeTimeHarness.new
tz_file = File.join(SaytimeWeather::Paths.tmp_dir, 'timezone')
File.write(tz_file, "Europe/Paris")

old_tz = ENV['TZ']
ENV['TZ'] = 'America/Chicago'

paris = IO.popen({ 'TZ' => 'Europe/Paris' }, ['date', '+%H']).read.strip.to_i
chicago = IO.popen({ 'TZ' => 'America/Chicago' }, ['date', '+%H']).read.strip.to_i
now = h.get_current_time('75001')

assert(paris != chicago, 'test setup: Paris and Chicago hours should differ')
assert(now.hour == paris, "location timezone file should win over ENV TZ (got #{now.hour}, expected #{paris})")

File.unlink(tz_file)
ENV.delete('TZ') unless old_tz
ENV['TZ'] = old_tz if old_tz

puts 'saytime_time_test: ok'
