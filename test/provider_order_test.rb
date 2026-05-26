#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'saytime_weather/weather_providers'

class ProviderOrderHarness
  include SaytimeWeather::WeatherProviders

  attr_accessor :config, :provider_explicitly_set, :options

  def initialize(config)
    @config = config
    @provider_explicitly_set = config.fetch(:explicit_provider, true)
    @options = { verbose: false }
  end

  def fetch_weather_nws(*) = nil
  def fetch_weather_metno(*) = nil
  def fetch_weather_wttr(*) = nil
  def fetch_weather_7timer(*) = nil
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

puts 'provider_order_test: ok'
