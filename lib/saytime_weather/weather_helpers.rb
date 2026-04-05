# frozen_string_literal: true

require 'json'

module SaytimeWeather
  module WeatherHelpers
    def warn(msg, critical = false)
      $stderr.puts "WARNING: #{msg}" if critical || @options[:verbose]
    end

    def error(msg)
      $stderr.puts "ERROR: #{msg}"
    end

    def temp_path(name)
      File.join(SaytimeWeather::Paths.tmp_dir, name)
    end

    def weather_sound_dir
      SaytimeWeather::Paths.weather_sound_dir
    end

    def safe_decode_json(content)
      return nil unless content && !content.empty?
      JSON.parse(content)
    rescue JSON::ParserError => e
      warn("JSON parse error: #{e.message}") if @options[:verbose]
      nil
    rescue => e
      warn("Unexpected error parsing JSON: #{e.message}") if @options[:verbose]
      nil
    end

    def parse_ini_file(file_path)
      Ini.parse_file(file_path)
    end

    def write_timezone_file(timezone)
      return unless timezone && !timezone.empty?

      File.write(temp_path('timezone'), timezone)
    rescue => e
      warn("Failed to write timezone file: #{e.message}")
    end
  end
end
