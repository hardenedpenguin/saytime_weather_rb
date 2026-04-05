#!/usr/bin/env ruby
# frozen_string_literal: true

# weather.rb - Weather retrieval script for saytime-weather (Ruby version)
# Copyright 2026 Jory A. Pratt, W5GLE
#
# - Fetches weather from Open-Meteo or NWS APIs (free, no API keys)
# - Supports postal codes, IATA airport codes (via Our Airports public CSV), ICAO codes, special locations
# - Creates sound files for temperature and conditions

_weather_entry = File.realpath(__FILE__)
_weather_root = File.dirname(_weather_entry)
_package = File.directory?(File.join(_weather_root, 'lib', 'saytime_weather')) ? _weather_root : File.expand_path('../share/saytime-weather-rb', _weather_root)
_lib = File.join(_package, 'lib')
$LOAD_PATH.unshift(_lib) unless $LOAD_PATH.include?(_lib)
require 'saytime_weather'
SaytimeWeather.root = _package

require 'uri'
require 'json'
require 'optparse'
require 'tempfile'
require 'fileutils'

class WeatherScript
  include SaytimeWeather::WeatherHelpers
  include SaytimeWeather::WeatherConfig
  include SaytimeWeather::WeatherUnits
  include SaytimeWeather::WeatherGeocoding
  include SaytimeWeather::WeatherAirports
  include SaytimeWeather::WeatherMetar
  include SaytimeWeather::WeatherOpenMeteo
  include SaytimeWeather::WeatherNws
  include SaytimeWeather::WeatherSound

  attr_reader :options, :config

  def initialize
    @options = {
      verbose: false,
      config_file: nil,
      default_country: nil,
      temperature_mode: nil,
      no_condition: false
    }
    @config = {}
    @provider_explicitly_set = false
    @airport_iata_map = nil
    parse_options
    @http = SaytimeWeather::HttpClient.new(warn_proc: ->(m) { warn(m) }, verbose: @options[:verbose])
    load_config
  end

  def parse_options
    parser = OptionParser.new do |opts|
      opts.banner = "weather.rb version #{SaytimeWeather::VERSION}\n\nUsage: #{File.basename($PROGRAM_NAME)} [OPTIONS] location_id [v]\n\n"

      opts.on('-c', '--config FILE', 'Use alternate configuration file') do |f|
        @options[:config_file] = f
      end

      opts.on('-d', '--default-country CC', 'Override default country (us, ca, fr, de, uk, etc.)') do |cc|
        @options[:default_country] = cc
      end

      opts.on('-t', '--temperature-mode M', 'Override temperature mode (F or C)') do |m|
        @options[:temperature_mode] = m.upcase
      end

      opts.on('--no-condition', 'Skip weather condition announcements') do
        @options[:no_condition] = true
      end

      opts.on('-v', '--verbose', 'Enable verbose output') do
        @options[:verbose] = true
      end

      opts.on('-h', '--help', 'Show this help message') do
        show_usage
        exit 0
      end

      opts.on('--version', 'Show version information') do
        puts "weather.rb version #{SaytimeWeather::VERSION}"
        exit 0
      end
    end

    parser.parse!
  end

  def show_usage
    puts "weather.rb version #{SaytimeWeather::VERSION}\n\n"
    puts "Usage: #{File.basename($PROGRAM_NAME)} [OPTIONS] location_id [v]\n\n"
    puts "Arguments:"
    puts "  location_id    Postal code, ZIP code, IATA airport code, or ICAO airport code"
    puts "                 IATA examples: JFK, LHR, CDG, DFW, SYD, NRT"
    puts "                 ICAO examples: KJFK, EGLL, CYYZ, NZSP, LFPG, RJAA"
    puts "  v              Optional: Display text only (verbose mode), no sound output\n\n"
    puts "Options:"
    puts "  -c, --config FILE        Use alternate configuration file"
    puts "  -d, --default-country CC Override default country (us, ca, fr, de, uk, etc.)"
    puts "  -t, --temperature-mode M Override temperature mode (F or C)"
    puts "  --no-condition           Skip weather condition announcements"
    puts "  -v, --verbose            Enable verbose output"
    puts "  -h, --help               Show this help message"
    puts "  --version                Show version information\n\n"
    puts "Examples:"
    puts "  Postal Codes:"
    puts "    #{File.basename($PROGRAM_NAME)} 90210                    # Beverly Hills, CA (ZIP)"
    puts "    #{File.basename($PROGRAM_NAME)} M5H2N2 v                 # Toronto, ON (postal code)"
    puts "    #{File.basename($PROGRAM_NAME)} -d fr 75001              # Paris, France"
    puts "    #{File.basename($PROGRAM_NAME)} -d de 10115 v            # Berlin, Germany\n\n"
    puts "  IATA Airport Codes (3 letters):"
    puts "    #{File.basename($PROGRAM_NAME)} JFK v                    # JFK Airport, New York"
    puts "    #{File.basename($PROGRAM_NAME)} LHR                      # Heathrow, London"
    puts "    #{File.basename($PROGRAM_NAME)} DFW v                    # Dallas/Fort Worth\n\n"
    puts "  ICAO Airport Codes (4 letters):"
    puts "    #{File.basename($PROGRAM_NAME)} KJFK v                   # JFK Airport, New York"
    puts "    #{File.basename($PROGRAM_NAME)} EGLL                     # Heathrow, London"
    puts "    #{File.basename($PROGRAM_NAME)} CYYZ v                   # Toronto Pearson\n\n"
    puts "Configuration File:"
    puts "  #{SaytimeWeather::Paths.config_path}\n\n"
    puts "Configuration Options:"
    puts "  - Temperature_mode: F/C (set to C for Celsius, F for Fahrenheit)"
    puts "  - process_condition: YES/NO (default: YES)"
    puts "  - default_country: ISO country code for postal lookups (default: us)"
    puts "  - weather_provider: openmeteo (worldwide) or nws (US only, default: openmeteo)"
    puts "  - show_precipitation: YES/NO (default: NO) - Units: inches (F) or mm (C)"
    puts "  - show_wind: YES/NO (default: NO) - Units: mph (F) or km/h (C)"
    puts "  - show_pressure: YES/NO (default: NO) - Units: inHG (F) or hPa (C)"
    puts "  - show_humidity: YES/NO (default: NO) - Shows relative humidity percentage"
    puts "  - show_zero_precip: YES/NO (default: NO) - Show precipitation even when zero"
    puts "  - precip_trace_mm: decimal (default: 0.10) - Minimum mm to show precipitation"
    puts "  - Optional: http_timeout_short, http_timeout_long, nominatim_delay, http_get_retries,"
    puts "    http_get_retry_sleep, airports_cache_max_age_seconds, airports_data_url\n\n"
    puts "Note: Command line options override configuration file settings for that run.\n"
  end

  def run
    @http.verbose = @options[:verbose]
    location = ARGV[0]
    display_only = ARGV[1]

    if location.nil? || location.empty?
      show_usage
      exit 0
    end

    unless location =~ /^[a-zA-Z0-9\s\-_]+$/
      error("Invalid location format. Only alphanumeric characters, spaces, hyphens, and underscores are allowed.")
      error("  Provided: #{location}")
      error("  Examples: 77511, M5H2N2, KJFK, ALERT")
      exit 1
    end

    location = location.strip

    cleanup_old_files

    temperature = nil
    condition = nil
    w_type = nil
    timezone = nil
    @weather_data = {}
    unless temperature && condition
      lat = nil
      lon = nil

      if iata_code?(location)
        icao = iata_to_icao(location)
        metar_temp, metar_cond = fetch_metar_weather(icao)

        if metar_temp && metar_cond
          temperature = metar_temp.round.to_s
          condition = metar_cond
          w_type = 'metar'
          @weather_data = { temp: metar_temp, condition: metar_cond }
        end
      elsif icao_code?(location)
        metar_temp, metar_cond = fetch_metar_weather(location)

        if metar_temp && metar_cond
          temperature = metar_temp.round.to_s
          condition = metar_cond
          w_type = 'metar'
          @weather_data = { temp: metar_temp, condition: metar_cond }
        end
      end

      unless temperature && condition
        lat, lon = postal_to_coordinates(location)

        if lat && lon
          temp = nil
          cond = nil
          tz = nil
          provider = @config['weather_provider'].to_s.downcase

          is_us_location = (lat >= 18.0 && lat <= 72.0 && lon >= -180.0 && lon <= -50.0)
          weather_data = nil
          if !@provider_explicitly_set && is_us_location
            weather_data = fetch_weather_nws(lat, lon)
            if weather_data && weather_data[:temp] && weather_data[:condition]
              provider = 'nws'
              w_type = 'nws'
            else
              weather_data = fetch_weather_openmeteo(lat, lon)
              provider = 'openmeteo'
            end
          elsif provider == 'nws'
            weather_data = fetch_weather_nws(lat, lon)

            unless weather_data && weather_data[:temp] && weather_data[:condition]
              weather_data = fetch_weather_openmeteo(lat, lon)
              provider = 'openmeteo'
            else
              w_type = 'nws'
            end
          else
            weather_data = fetch_weather_openmeteo(lat, lon)
            provider = 'openmeteo'
          end

          if weather_data && weather_data[:temp] && weather_data[:condition]
            temperature = weather_data[:temp].to_s
            condition = weather_data[:condition]
            timezone = weather_data[:timezone]
            @weather_data = weather_data
            w_type = provider unless w_type
            warn("Weather from #{provider.upcase}") if @options[:verbose]

          else
            provider_name = provider.upcase
            error("Failed to fetch weather data from #{provider_name}")
            error("  Location: #{location}")
            error("  Coordinates: lat=#{lat}, lon=#{lon}")
            error("  Hint: Check internet connectivity and API availability")
            if provider == 'nws'
              error("  Note: NWS only supports US locations")
            end
          end
        else
          error("Could not get coordinates for location: #{location}")
          error("  Hint: Verify the postal code or location name is correct")
          error("  For IATA codes (3 letters), ensure the airport code is valid (e.g., JFK, LHR, DFW)")
          error("  For ICAO codes (4 letters), ensure the airport code is valid (e.g., KJFK, EGLL)")
        end

        w_type ||= 'openmeteo'
      end
    end

    unless temperature && condition
      error("No weather report available")
      error("  Location: #{location}")
      error("  Hint: Check that the location is valid and weather services are accessible")
      exit 1
    end

    temp_f = temperature.to_f
    unless temp_f >= -150.0 && temp_f <= 200.0
      error("Invalid temperature value: #{temp_f}°F")
      error("  Location: #{location}")
      exit 1
    end
    temp_c = ((5.0 / 9.0) * (temp_f - 32)).round

    temp_f_display = temp_f.round

    output_parts = ["#{temp_f_display}°F, #{temp_c}°C"]

    temp_mode = @config['Temperature_mode']
    weather_data = @weather_data || {}

    if @config['show_humidity'] == 'YES' && weather_data[:humidity]
      humidity_val = weather_data[:humidity]
      if humidity_val && humidity_val.is_a?(Numeric)
        output_parts << "#{humidity_val.round}% RH"
      end
    end

    output_parts << condition

    if @config['show_precipitation'] == 'YES' && weather_data[:precipitation]
      precip_mm = weather_data[:precipitation]
      if precip_mm && precip_mm.is_a?(Numeric)
        show_precip = false
        if precip_mm > 0
          show_precip = true
        elsif @config['show_zero_precip'] == 'YES'
          show_precip = true
        end

        if show_precip && precip_mm > 0
          trace_threshold = @config['precip_trace_mm'].to_f
          if precip_mm < trace_threshold && @config['show_zero_precip'] != 'YES'
            show_precip = false
          end
        end

        if show_precip
          if temp_mode == 'F'
            precip_in = mm_to_inches(precip_mm)
            output_parts << "Precip #{precip_in} in" if precip_in
          else
            output_parts << "Precip #{precip_mm.round(2)} mm"
          end
        end
      end
    end

    if @config['show_wind'] == 'YES' && weather_data[:wind_speed]
      wind_ms = weather_data[:wind_speed]
      if wind_ms && wind_ms.is_a?(Numeric) && wind_ms > 0
        wind_str = "Wind"
        if temp_mode == 'F'
          wind_mph = ms_to_mph(wind_ms)
          wind_str += " #{wind_mph} mph" if wind_mph
        else
          wind_kmh = ms_to_kmh(wind_ms)
          wind_str += " #{wind_kmh} km/h" if wind_kmh
        end

        if weather_data[:wind_direction] && weather_data[:wind_direction].is_a?(Numeric)
          dir = wind_direction_to_cardinal(weather_data[:wind_direction])
          wind_str += " #{dir}" if dir
        end

        if weather_data[:wind_gusts] && weather_data[:wind_gusts].is_a?(Numeric) && weather_data[:wind_gusts] > wind_ms
          if temp_mode == 'F'
            gust_mph = ms_to_mph(weather_data[:wind_gusts])
            wind_str += " (gust #{gust_mph})" if gust_mph
          else
            gust_kmh = ms_to_kmh(weather_data[:wind_gusts])
            wind_str += " (gust #{gust_kmh})" if gust_kmh
          end
        end

        output_parts << wind_str
      end
    end

    if @config['show_pressure'] == 'YES' && weather_data[:pressure]
      pressure_hpa = weather_data[:pressure]
      if pressure_hpa && pressure_hpa.is_a?(Numeric)
        if temp_mode == 'F'
          pressure_inhg = hpa_to_inhg(pressure_hpa)
          output_parts << "#{pressure_inhg} inHG" if pressure_inhg
        else
          output_parts << "#{pressure_hpa.round} hPa"
        end
      end
    end

    puts output_parts.join(' / ')

    exit 0 if display_only == 'v'

    temp_mode = @config['Temperature_mode']
    tmin = temp_mode == 'C' ? -60 : -100
    tmax = temp_mode == 'C' ? 60 : 150
    temp_value = temp_mode == 'C' ? temp_c : temp_f

    if temp_value >= tmin && temp_value <= tmax
      begin
        File.write(temp_path('temperature'), temp_value.round.to_s)
      rescue => e
        warn("Error writing temperature file: #{e.message}")
      end
    end

    if @config['process_condition'] == 'YES' && condition
      process_weather_condition(condition)
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  script = WeatherScript.new
  script.run
end
