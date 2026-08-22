#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tmpdir'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'saytime_weather'

def assert(condition, msg)
  raise msg unless condition
end

def assert_includes(haystack, needle, msg = nil)
  assert(haystack.include?(needle), msg || "expected #{needle.inspect} in #{haystack.inspect}")
end

class WeatherAudioHarness
  include SaytimeWeather::SaytimePlayback
  include SaytimeWeather::SaytimeTime
  include SaytimeWeather::WeatherAudio
  include SaytimeWeather::SoundIndex

  attr_accessor :options, :config

  def initialize(sound_dir)
    @options = { verbose: false, custom_sound_dir: sound_dir }
    @config = { 'Temperature_mode' => 'F' }
  end
end

Dir.mktmpdir do |dir|
  wx = File.join(dir, 'wx')
  digits = File.join(dir, 'digits')
  FileUtils.mkdir_p(wx)
  FileUtils.mkdir_p(digits)

  %w[feels-like dewpoint humidity percent wind gust pressure precipitation uv-index visibility
     point miles-per-hour inches-of-mercury inches miles degrees weather conditions temperature
     southwest].each do |name|
    FileUtils.touch(File.join(wx, "#{name}.ulaw"))
  end

  (0..20).each { |n| FileUtils.touch(File.join(digits, "#{n}.ulaw")) }
  [30, 12, 15, 22, 7, 88, 65].each { |n| FileUtils.touch(File.join(digits, "#{n}.ulaw")) }
  FileUtils.touch(File.join(digits, 'minus.ulaw'))
  FileUtils.touch(File.join(dir, 'silence', '1.ulaw')) rescue FileUtils.mkdir_p(File.join(dir, 'silence'))
  FileUtils.touch(File.join(dir, 'silence', '1.ulaw'))

  h = WeatherAudioHarness.new(dir)
  extras = [
    { 'k' => 'humidity', 'v' => 65 },
    { 'k' => 'feels_like', 'v' => 88 },
    { 'k' => 'wind', 'speed' => 15, 'dir' => 'SW', 'gust' => 22 },
    { 'k' => 'pressure', 'v' => 30.12 },
    { 'k' => 'uv', 'v' => 7 }
  ]

  audio = h.build_weather_extras_audio(extras, dir, 'F')
  assert_includes(audio, 'humidity.ulaw')
  assert_includes(audio, 'feels-like.ulaw')
  assert_includes(audio, 'wind.ulaw')
  assert_includes(audio, 'southwest.ulaw')
  assert_includes(audio, 'gust.ulaw')
  assert_includes(audio, 'point.ulaw')
  assert_includes(audio, 'inches-of-mercury.ulaw')
  assert_includes(audio, 'uv-index.ulaw')
  assert_includes(audio, 'digits/65.ulaw')
  assert_includes(audio, 'digits/15.ulaw')
end

puts 'weather_audio_test: ok'
