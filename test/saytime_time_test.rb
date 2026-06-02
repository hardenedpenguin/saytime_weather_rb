#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'saytime_weather/saytime_playback'
require 'saytime_weather/saytime_time'
require 'saytime_weather/paths'

class SaytimeTimeHarness
  include SaytimeWeather::SaytimePlayback
  include SaytimeWeather::SaytimeTime

  def initialize(options = {})
    @options = {
      verbose: false,
      greeting_enabled: false,
      custom_sound_dir: '/fake/sounds/en'
    }.merge(options)
    @missing_files = 0
  end

  def indexed_file_exists?(_path)
    true
  end

  def time_at(hour, minute)
    Time.new(2026, 1, 1, hour, minute, 0)
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

FAKE_SND = '/fake/sounds/en'
h12 = SaytimeTimeHarness.new

def assert_12h_files(out, hour_digit:, minute_files:, am_pm:, oh: false)
  assert(out.include?("#{FAKE_SND}/digits/#{hour_digit}.ulaw"), "hour digit #{hour_digit} in #{out}")
  assert(out.include?("#{FAKE_SND}/digits/#{am_pm}.ulaw") || out.include?("#{FAKE_SND}/#{am_pm}.ulaw"),
         "am/pm #{am_pm} in #{out}")
  minute_files.each do |frag|
    assert(out.include?(frag), "expected #{frag} in #{out}")
  end
  has_oh = out.include?('letters/o.ulaw') || out.match?(%r{digits/0\.ulaw })
  assert(has_oh, 'expected oh (letters/o or digits/0)') if oh
  assert(!has_oh, "did not expect oh in #{out}") unless oh
end

# 2:06 AM -> two oh six + a-m
out = h12.process_time(h12.time_at(2, 6), false)
assert_12h_files(out, hour_digit: 2, minute_files: ['digits/6.ulaw'], am_pm: 'a-m', oh: true)

# 2:10 PM -> two ten + p-m (no oh)
out = h12.process_time(h12.time_at(14, 10), false)
assert_12h_files(out, hour_digit: 2, minute_files: ['digits/10.ulaw'], am_pm: 'p-m', oh: false)

# 2:00 PM -> two + p-m only
out = h12.process_time(h12.time_at(14, 0), false)
assert_12h_files(out, hour_digit: 2, minute_files: [], am_pm: 'p-m', oh: false)
assert(!out.include?('digits/0.ulaw'), 'on the hour should not play zero')

# 12:30 AM -> twelve thirty + a-m
out = h12.process_time(h12.time_at(0, 30), false)
assert_12h_files(out, hour_digit: 12, minute_files: ['digits/30.ulaw'], am_pm: 'a-m', oh: false)

# noon -> twelve + p-m
out = h12.process_time(h12.time_at(12, 0), false)
assert_12h_files(out, hour_digit: 12, minute_files: [], am_pm: 'p-m', oh: false)

puts 'saytime_time_test: ok'
