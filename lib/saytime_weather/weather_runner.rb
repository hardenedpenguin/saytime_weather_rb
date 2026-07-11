# frozen_string_literal: true

require_relative 'config_error'

module SaytimeWeather
  # Run weather retrieval in-process (same behavior as weather.rb).
  # Returns true on success, false on failure.
  def self.run_weather(location, options = {})
    require_relative 'weather_script'
    script = WeatherScript.new(options: normalize_weather_options(options))
    display_only = options[:display_only] ? 'v' : nil
    script.run(location: location, display_only: display_only)
  rescue ConfigError => e
    $stderr.puts "ERROR: #{e.message}"
    false
  end

  def self.normalize_weather_options(options)
    opts = {}
    opts[:verbose] = true if options[:verbose]
    opts[:config_file] = options[:config_file] if options[:config_file]
    opts[:default_country] = options[:default_country] if options[:default_country]
    opts[:temperature_mode] = options[:temperature_mode] if options[:temperature_mode]
    opts[:no_condition] = true if options[:no_condition]
    opts[:use_gps] = true if options[:use_gps]
    opts[:custom_sound_dir] = options[:custom_sound_dir] if options[:custom_sound_dir]
    opts
  end
end
