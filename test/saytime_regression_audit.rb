#!/usr/bin/env ruby
# frozen_string_literal: true

# Layout/regression audit for 12-hour paths. Also run via: make test-unit

require 'fileutils'
require 'tmpdir'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'saytime_weather/saytime_playback'
require 'saytime_weather/saytime_time'

class AuditHarness
  include SaytimeWeather::SaytimePlayback
  include SaytimeWeather::SaytimeTime

  def initialize(sound_dir)
    @options = { custom_sound_dir: sound_dir, verbose: false, greeting_enabled: false }
    @missing_files = 0
  end

  def indexed_file_exists?(path)
    File.exist?(path)
  end
end

def assert!(cond, msg)
  raise msg unless cond
end

def touch(*paths)
  paths.each do |p|
    FileUtils.mkdir_p(File.dirname(p))
    File.write(p, 'x') unless File.exist?(p)
  end
end

errors = []

Dir.mktmpdir do |root|
  sd = File.join(root, 'en')
  touch(
    File.join(sd, 'digits/a-m.ulaw'),
    File.join(sd, 'digits/p-m.ulaw'),
    File.join(sd, 'digits/2.ulaw'),
    File.join(sd, 'digits/6.ulaw'),
    File.join(sd, 'digits/7.ulaw'),
    File.join(sd, 'digits/10.ulaw'),
    File.join(sd, 'digits/12.ulaw'),
    File.join(sd, 'digits/15.ulaw'),
    File.join(sd, 'digits/30.ulaw'),
    File.join(sd, 'rpt/thetimeis.ulaw')
  )
  h = AuditHarness.new(sd)

  assert!(h.meridian_sound_path(sd, 'p-m').end_with?('/digits/p-m.ulaw'),
          'meridian must prefer digits/p-m')

  touch(File.join(sd, 'p-m.ulaw'))
  assert!(h.meridian_sound_path(sd, 'p-m').end_with?('/digits/p-m.ulaw'),
          'meridian must still prefer digits when en/p-m exists')

  scenarios = [
    [19, 15, '7', '15', 'p-m', false], # minute >= 10: no "oh"
    [14, 10, '2', '10', 'p-m', false],
    [2, 6, '2', '6', 'a-m', true],      # minute 1-9: "oh"
    [14, 0, '2', nil, 'p-m', false]
  ]
  scenarios.each do |hr, min, dh, min_file, ap, expect_oh|
    out = h.process_time(Time.new(2026, 6, 2, hr, min, 0), false).split
    dh_i = out.index { |p| p.end_with?("/digits/#{dh}.ulaw") }
    ap_i = out.index { |p| p.include?("#{ap}.ulaw") }
    assert!(dh_i, "#{hr}:#{min} missing hour #{dh}")
    assert!(ap_i, "#{hr}:#{min} missing #{ap}")
    if min_file
      mi_i = out.index { |p| p.end_with?("/digits/#{min_file}.ulaw") }
      assert!(mi_i && dh_i < mi_i && mi_i < ap_i, "#{hr}:#{min} bad order: #{out}")
    else
      assert!(dh_i < ap_i, "#{hr}:00 bad order")
      assert!(!out.any? { |p| p.end_with?('/digits/0.ulaw') }, "#{hr}:00 should not play zero")
    end
    has_oh = out.any? { |p| p.include?('letters/o') || p.end_with?('/digits/0.ulaw') }
    assert!(has_oh == expect_oh, "#{hr}:#{min} oh=#{has_oh} expected #{expect_oh}")
  end

  touch(File.join(sd, 'hours.ulaw'))
  assert!(h.sound_path(sd, 'hours.ulaw').end_with?('/hours.ulaw'),
          'hours should resolve under en/ when only en/hours exists')
  assert!(!h.sound_path(sd, 'hours.ulaw').include?('/digits/hours'),
          'hours must not use nonexistent digits/hours')

  (0..23).each do |hr|
    out = h.process_time(Time.new(2026, 6, 2, hr, 0, 0), false)
    exp = hr < 12 ? 'a-m' : 'p-m'
    assert!(out.include?("digits/#{exp}"), "hour #{hr}:00 missing digits/#{exp}")
  end

  (0..23).each do |hr|
    out = h.process_time(Time.new(2026, 6, 2, hr, 0, 0), true)
    assert!(!out.include?('a-m') && !out.include?('p-m'), "24h hour #{hr} leaked meridian")
  end
end

puts 'saytime_regression_audit: ok'
