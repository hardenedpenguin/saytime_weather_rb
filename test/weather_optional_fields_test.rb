#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'tmpdir'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'saytime_weather'

def assert(condition, msg)
  raise msg unless condition
end

class OptionalFieldsHarness
  include SaytimeWeather::WeatherOptionalFields
  include SaytimeWeather::WeatherOpenMeteo

  attr_accessor :config

  def initialize(config)
    @config = config
  end
end

h = OptionalFieldsHarness.new(
  'show_feels_like' => 'YES',
  'announce_feels_like' => 'NO'
)
assert(h.optional_weather_field_enabled?('show_feels_like'), 'show enables data fetch')
assert(!h.optional_weather_announce_enabled?('show_feels_like'), 'announce off when NO')
params = h.open_meteo_current_params(include_extras: true)
assert(params.include?('apparent_temperature'), 'show_feels_like requests Open-Meteo field')

h2 = OptionalFieldsHarness.new(
  'show_feels_like' => 'NO',
  'announce_feels_like' => 'YES'
)
assert(h2.optional_weather_field_enabled?('show_feels_like'), 'announce alone enables data fetch')
assert(h2.optional_weather_announce_enabled?('show_feels_like'), 'announce enables audio flag')
params2 = h2.open_meteo_current_params(include_extras: true)
assert(params2.include?('apparent_temperature'), 'announce_feels_like requests Open-Meteo field')

Dir.mktmpdir do |dir|
  ini = File.join(dir, 'weather.ini')
  File.write(ini, <<~INI)
    [weather]
    Temperature_mode = F
    weather_provider = openmeteo
    weather_provider_random = NO
    show_feels_like = NO
    announce_feels_like = YES
  INI

  SaytimeWeather::RunContext.begin_run!
  script = SaytimeWeather::WeatherScript.new(options: { config_file: ini })
  script.instance_variable_set(:@weather_data, { feels_like: 90.0 })
  script.send(:write_weather_extras_file)
  extras_path = SaytimeWeather::RunContext.scoped_tmp_path('weather_extras.json')
  assert(File.exist?(extras_path), 'announce without show should write extras file')
  import = JSON.parse(File.read(extras_path))
  assert(import.any? { |s| s['k'] == 'feels_like' }, 'feels_like segment present')
  SaytimeWeather::RunContext.cleanup!
end

puts 'weather_optional_fields_test: ok'
