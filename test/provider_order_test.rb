#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'json'
require 'saytime_weather/network'
require 'saytime_weather/weather_geocoding'
require 'saytime_weather/weather_airports'
require 'saytime_weather/weather_weatherapi'
require 'saytime_weather/weather_providers'

class ProviderOrderHarness
  include SaytimeWeather::WeatherGeocoding
  include SaytimeWeather::WeatherAirports
  include SaytimeWeather::WeatherWeatherapi
  include SaytimeWeather::WeatherProviders

  attr_accessor :config, :provider_explicitly_set, :options

  def initialize(config)
    @config = config
    @provider_explicitly_set = config.fetch(:explicit_provider, true)
    @options = { verbose: false }
    SaytimeWeather::Network.reset_defaults!
  end

  def fetch_weather_nws(*) = nil
  def fetch_weather_metno(*) = nil
  def fetch_weather_wttr(*) = nil
  def fetch_weather_7timer(*) = nil
  def fetch_weather_weatherapi(*) = nil
  def fetch_weather_openmeteo(*) = nil
  def warn(*) = nil
end

def assert(condition, msg)
  raise msg unless condition
end

h = ProviderOrderHarness.new(
  'weather_provider' => 'openmeteo',
  'weather_provider_random' => 'YES',
  explicit_provider: true
)
order = h.provider_try_order_random(52.52, 13.41) # Berlin
assert(!order.include?('openmeteo') || order.last == 'openmeteo', 'default openmeteo should be last')
assert(order.first != 'openmeteo', 'random pool should not start with default')
assert((order & %w[metno wttr 7timer]).any?, 'should include worldwide alternates')

h2 = ProviderOrderHarness.new(
  'weather_provider' => 'openmeteo',
  'weather_provider_random' => 'NO',
  explicit_provider: false
)
us_order = h2.provider_try_order_fixed(40.0, -75.0)
assert(us_order == %w[nws openmeteo], 'implicit US default tries NWS first')

h3 = ProviderOrderHarness.new('weather_provider' => 'nws', 'weather_provider_random' => 'NO')
berlin = h3.provider_try_order_fixed(52.52, 13.41)
assert(berlin == %w[openmeteo], 'nws config outside US should use openmeteo only')

h4 = ProviderOrderHarness.new(
  'weather_provider' => 'openmeteo',
  'weather_provider_random' => 'YES',
  'weather_provider_random_max_attempts' => '2',
  explicit_provider: true
)
order = h4.provider_try_order_random(52.52, 13.41)
assert(order.length == 2, 'max attempts 2 should yield one alternate plus default')
assert(order.last == 'openmeteo', 'default should be last')

h5 = ProviderOrderHarness.new('weatherapi_key' => 'k', 'weather_provider' => 'openmeteo')
with_key = h5.eligible_providers(52.52, 13.41)
assert(with_key.include?('weatherapi'), 'weatherapi should be eligible when key is set')

h6 = ProviderOrderHarness.new('weather_provider' => 'openmeteo')
without_key = h6.eligible_providers(52.52, 13.41)
assert(!without_key.include?('weatherapi'), 'weatherapi should not rotate without a key')

h7 = ProviderOrderHarness.new(
  'weather_provider' => 'openmeteo',
  'weather_provider_random' => 'YES',
  explicit_provider: true
)
50.times do
  order = h7.provider_try_order_random(52.52, 13.41)
  assert(!order.include?('weatherapi'), 'random order must not include weatherapi without a key')
  us_order = h7.provider_try_order_random(40.0, -75.0)
  assert(!us_order.include?('weatherapi'), 'US random order must not include weatherapi without a key')
end

prev = ENV['WEATHERAPI_KEY']
ENV.delete('WEATHERAPI_KEY')
h8 = ProviderOrderHarness.new('weatherapi_key' => '  ', 'weather_provider' => 'openmeteo')
assert(!h8.weatherapi_available?, 'whitespace-only key must not enable weatherapi')
assert(!h8.eligible_providers(52.52, 13.41).include?('weatherapi'), 'whitespace key must not enter rotation')
ENV['WEATHERAPI_KEY'] = prev if prev

puts 'provider_order_test: ok'
