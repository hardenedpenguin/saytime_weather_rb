# frozen_string_literal: true

module SaytimeWeather
  # Run weather retrieval in-process (same behavior as weather.rb).
  # Returns true on success, false on failure.
  def self.run_weather(location, options = {})
    require_relative 'weather_script'
    script = WeatherScript.new(options: normalize_weather_options(options))
    display_only = options[:display_only] ? 'v' : nil
    script.run(location: location, display_only: display_only)
  end

  def self.normalize_weather_options(options)
    opts = {}
    opts[:verbose] = true if options[:verbose]
    opts[:config_file] = options[:config_file] if options[:config_file]
    opts[:default_country] = options[:default_country] if options[:default_country]
    opts[:temperature_mode] = options[:temperature_mode] if options[:temperature_mode]
    opts[:no_condition] = true if options[:no_condition]
    opts
  end
end
