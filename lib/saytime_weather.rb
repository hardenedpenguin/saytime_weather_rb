# frozen_string_literal: true

module SaytimeWeather
  class << self
    attr_accessor :root
  end
end

require_relative 'saytime_weather/version'
require_relative 'saytime_weather/network'
require_relative 'saytime_weather/paths'
require_relative 'saytime_weather/endpoints'
require_relative 'saytime_weather/http_client'
