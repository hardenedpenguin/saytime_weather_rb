#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

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
    @info_log = []
  end

  def indexed_file_exists?(_path)
    true
  end

  def info(msg)
    @info_log << msg
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
  ap = "#{FAKE_SND}/#{am_pm}.ulaw"
  ap_digits = "#{FAKE_SND}/digits/#{am_pm}.ulaw"
  assert(out.include?(ap) || out.include?(ap_digits), "am/pm #{am_pm} in #{out}")
  hour_pos = out.index("#{FAKE_SND}/digits/#{hour_digit}.ulaw")
  ap_pos = out.index(ap) || out.index(ap_digits)
  minute_files.each do |frag|
    assert(out.include?(frag), "expected #{frag} in #{out}")
    assert(out.index(frag) > hour_pos, "minute #{frag} should follow hour") if hour_pos
    assert(out.index(frag) < ap_pos, "minute #{frag} should precede meridian") if ap_pos
  end
  assert(ap_pos > hour_pos, 'meridian should follow hour') if ap_pos && hour_pos
  assert(ap_pos > out.index(minute_files.last), 'meridian should follow minutes') if ap_pos && !minute_files.empty?
  has_oh = out.include?('letters/o.ulaw') || out.match?(%r{digits/0\.ulaw })
  assert(has_oh, 'expected oh (letters/o or digits/0)') if oh
  assert(!has_oh, "did not expect oh in #{out}") unless oh
end

# 7:15 PM -> seven fifteen p-m (meridian after minutes)
out = h12.process_time(h12.time_at(19, 15), false)
parts = out.split
h_pos = parts.index { |p| p.end_with?('/digits/7.ulaw') }
m_pos = parts.index { |p| p.end_with?('/digits/15.ulaw') }
ap_pos = parts.index { |p| p.include?('p-m.ulaw') }
assert(h_pos && m_pos && ap_pos && h_pos < m_pos && m_pos < ap_pos, "7:15 PM order: hour then minute then p-m (#{parts})")

# Meridian prefers digits/a-m over en/a-m when both exist (stock Asterisk layout)
mer_dir = File.join(Dir.mktmpdir, 'en')
FileUtils.mkdir_p(File.join(mer_dir, 'digits'))
File.write(File.join(mer_dir, 'digits', 'p-m.ulaw'), 'STOCK')
File.write(File.join(mer_dir, 'p-m.ulaw'), 'PACKAGE')
h_mer = SaytimeTimeHarness.new(custom_sound_dir: mer_dir)
def h_mer.indexed_file_exists?(path)
  File.exist?(path)
end
assert(h_mer.meridian_sound_path(mer_dir, 'p-m').end_with?('/digits/p-m.ulaw'), 'p-m should resolve to digits/')
FileUtils.rm_rf(File.dirname(mer_dir))

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

# Regression: 2 PM must be afternoon + p-m (not a-m from display digit 2)
hg = SaytimeTimeHarness.new(greeting_enabled: true)
out = hg.process_time(hg.time_at(14, 15), false)
assert(out.include?("#{FAKE_SND}/rpt/goodafternoon.ulaw"), '2:15 PM should greet afternoon')
assert_12h_files(out, hour_digit: 2, minute_files: ['digits/15.ulaw'], am_pm: 'p-m', oh: false)

# Greeting and meridian must stay aligned for every hour (catches display_hour vs hour24 bugs)
(0..23).each do |hour|
  h = SaytimeTimeHarness.new(greeting_enabled: true)
  out = h.process_time(h.time_at(hour, 0), false)
  exp_g = hour < 12 ? 'morning' : (hour < 18 ? 'afternoon' : 'evening')
  exp_ap = hour < 12 ? 'a-m' : 'p-m'
  assert(out.include?("#{FAKE_SND}/rpt/good#{exp_g}.ulaw"),
         "hour #{hour}: expected good#{exp_g}")
  assert(out.include?("#{FAKE_SND}/digits/#{exp_ap}.ulaw"),
         "hour #{hour}: meridian should resolve under digits/")
end

# 24-hour mode: no a-m/p-m; afternoon hour uses 14 + hours
h24 = SaytimeTimeHarness.new
out = h24.process_time(h24.time_at(14, 30), true)
assert(out.include?('digits/14.ulaw'), '14:30 24h should say fourteen')
assert(out.include?('hours.ulaw'), '24h non-zero minutes should end with hours')
assert(!out.include?('a-m.ulaw') && !out.include?('p-m.ulaw'), '24h must not play meridian')

assert(hg.greeting_for_hour24(8) == 'morning', '8:00 is morning greeting')
assert(hg.greeting_for_hour24(14) == 'afternoon', '14:00 is afternoon greeting')
assert(hg.greeting_for_hour24(20) == 'evening', '20:00 is evening greeting')
assert(hg.meridian_sound(14) == 'p-m', '14:00 is p-m')
assert(hg.meridian_sound(2) == 'a-m', '02:00 is a-m')
assert(hg.twelve_hour_display(14) == 2, '14:00 displays as 2')
assert(hg.twelve_hour_display(0) == 12, 'midnight displays as 12')

puts 'saytime_time_test: ok'
