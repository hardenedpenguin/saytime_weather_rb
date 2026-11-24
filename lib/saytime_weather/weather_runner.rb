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

  # Options saytime.rb may pass to WeatherScript (single source of truth for
  # in-process runs, WeatherScript#merge_runtime_options, and tests).
  WEATHER_RUNTIME_OPTION_KEYS = %i[
    verbose config_file default_country temperature_mode no_condition use_gps custom_sound_dir
  ].freeze

  # Keep only known keys with a meaningful value (nil / false / empty string are dropped).
  def self.normalize_weather_options(options)
    WEATHER_RUNTIME_OPTION_KEYS.each_with_object({}) do |key, out|
      val = options[key]
      next if val.nil? || val == false || (val.respond_to?(:empty?) && val.empty?)

      out[key] = val
    end
  end
end
