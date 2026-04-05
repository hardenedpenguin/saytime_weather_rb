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

require 'csv'
require 'uri'
require 'json'
require 'optparse'
require 'tempfile'
require 'fileutils'

HTTP_BUFFER_SIZE = 8192

class WeatherScript
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

  def load_config
    config_path = @options[:config_file] || SaytimeWeather::Paths.config_path
    
    if @options[:config_file] && !File.exist?(@options[:config_file])
      $stderr.puts "ERROR: Custom config file not found: #{@options[:config_file]}"
      exit 1
    end
    
    if File.exist?(config_path)
      begin
        ini = parse_ini_file(config_path)
        if ini && ini['weather']
          @config = ini['weather'].merge(@config)
          @provider_explicitly_set = ini['weather'].key?('weather_provider')
        end
      rescue => e
        warn("Failed to parse config file #{config_path}: #{e.message}")
      end
    else
      begin
        create_default_config(config_path)
      rescue => e
        warn("Could not create config file #{config_path}: #{e.message}")
      end
    end
    
    # Set defaults
    @config['process_condition'] ||= 'YES'
    @config['Temperature_mode'] ||= 'F'
    @config['default_country'] ||= 'us'
    @config['weather_provider'] ||= 'openmeteo'
    @config['show_precipitation'] ||= 'NO'
    @config['show_wind'] ||= 'NO'
    @config['show_pressure'] ||= 'NO'
    @config['show_humidity'] ||= 'NO'
    @config['show_zero_precip'] ||= 'NO'
    @config['precip_trace_mm'] ||= '0.10'
    
    # Apply command line overrides
    @config['default_country'] = @options[:default_country] if @options[:default_country]
    @config['Temperature_mode'] = @options[:temperature_mode] if @options[:temperature_mode]
    @config['process_condition'] = 'NO' if @options[:no_condition]
    
    validate_config
    apply_network_settings
  end

  def apply_network_settings
    n = SaytimeWeather::Network
    n.timeout_short = @config['http_timeout_short'].to_i if @config['http_timeout_short'].to_s =~ /^\d+$/
    n.timeout_long = @config['http_timeout_long'].to_i if @config['http_timeout_long'].to_s =~ /^\d+$/
    n.nominatim_delay = @config['nominatim_delay'].to_i if @config['nominatim_delay'].to_s =~ /^\d+$/
    n.retries = @config['http_get_retries'].to_i if @config['http_get_retries'].to_s =~ /^\d+$/
    n.retry_sleep = @config['http_get_retry_sleep'].to_i if @config['http_get_retry_sleep'].to_s =~ /^\d+$/
    if @config['airports_cache_max_age_seconds'].to_s =~ /^\d+$/
      n.airports_cache_max_age = @config['airports_cache_max_age_seconds'].to_i
    end
    url = @config['airports_data_url'].to_s.strip
    n.airports_data_url = url unless url.empty?
  end

  def create_default_config(config_path)
    FileUtils.mkdir_p(File.dirname(config_path)) unless Dir.exist?(File.dirname(config_path))
    default_config = <<~CONFIG
      [weather]
      Temperature_mode = F
      process_condition = YES
      default_country = us
      weather_provider = openmeteo
      show_precipitation = NO
      show_wind = NO
      show_pressure = NO
      show_humidity = NO
      show_zero_precip = NO
      precip_trace_mm = 0.10
      ; Optional network tuning (defaults shown; uncomment to override)
      ; http_timeout_short = 10
      ; http_timeout_long = 15
      ; nominatim_delay = 1
      ; http_get_retries = 3
      ; http_get_retry_sleep = 1
      ; airports_cache_max_age_seconds = 604800
      ; airports_data_url = https://ourairports.com/data/airports.csv
    CONFIG
    File.write(config_path, default_config)
    File.chmod(0o644, config_path)
  end

  def validate_config
    temp_mode = @config['Temperature_mode'].to_s
    unless temp_mode =~ /^[CF]$/
      error("Invalid Temperature_mode: #{@config['Temperature_mode']}")
      exit 1
    end
    
    provider = @config['weather_provider'].to_s.downcase
    unless %w[openmeteo nws].include?(provider)
      warn("Invalid weather_provider: #{@config['weather_provider']}, using default (openmeteo)")
      @config['weather_provider'] = 'openmeteo'
    end
  end

  def run
    @http.verbose = @options[:verbose]
    location = ARGV[0]
    display_only = ARGV[1]
    
    # Validate location input
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
    
    # Fetch weather
    temperature = nil
    condition = nil
    w_type = nil
    timezone = nil
    @weather_data = {}  # Store additional weather data
    unless temperature && condition
      lat = nil
      lon = nil
      
      # Try IATA codes first (convert to ICAO and fetch METAR)
      if iata_code?(location)
        icao = iata_to_icao(location)
        metar_temp, metar_cond = fetch_metar_weather(icao)
        
        if metar_temp && metar_cond
          temperature = metar_temp.round.to_s
          condition = metar_cond
          w_type = 'metar'
          @weather_data = { temp: metar_temp, condition: metar_cond }  # METAR doesn't provide additional data
        # else: METAR fetch failed, fall through to postal code lookup
        end
      # Try ICAO/METAR if not IATA
      elsif icao_code?(location)
        metar_temp, metar_cond = fetch_metar_weather(location)
        
        if metar_temp && metar_cond
          temperature = metar_temp.round.to_s
          condition = metar_cond
          w_type = 'metar'
          @weather_data = { temp: metar_temp, condition: metar_cond }  # METAR doesn't provide additional data
        # else: METAR fetch failed, fall through to postal code lookup
        end
      end
      
      # Try postal code lookup
      unless temperature && condition
        lat, lon = postal_to_coordinates(location)
        
        if lat && lon
          temp = nil
          cond = nil
          tz = nil
          provider = @config['weather_provider'].to_s.downcase
          
          # Auto-detect US locations and prefer NWS if provider not explicitly set in config
          is_us_location = (lat >= 18.0 && lat <= 72.0 && lon >= -180.0 && lon <= -50.0)
          weather_data = nil
          if !@provider_explicitly_set && is_us_location
            # Provider not explicitly set and this is a US location - try NWS first (matches Perl behavior)
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
            # Don't round temperature here - keep as float for display, round only for file output
            temperature = weather_data[:temp].to_s
            condition = weather_data[:condition]
            timezone = weather_data[:timezone]
            @weather_data = weather_data  # Store for display
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
        
        # Only set default provider if we still don't have a type
        w_type ||= 'openmeteo'
      end
    end
    
    unless temperature && condition
      error("No weather report available")
      error("  Location: #{location}")
      error("  Hint: Check that the location is valid and weather services are accessible")
      exit 1
    end
    
    # Convert to Celsius if needed
    temp_f = temperature.to_f
    # Validate temperature is reasonable before conversion
    unless temp_f >= -150.0 && temp_f <= 200.0
      error("Invalid temperature value: #{temp_f}°F")
      error("  Location: #{location}")
      exit 1
    end
    temp_c = ((5.0 / 9.0) * (temp_f - 32)).round
    
    # Round temperature to whole number for display
    temp_f_display = temp_f.round
    
    # Build output string
    output_parts = ["#{temp_f_display}°F, #{temp_c}°C"]
    
    # Initialize weather_data early for use in all sections
    temp_mode = @config['Temperature_mode']
    weather_data = @weather_data || {}
    
    # Humidity (shown early, before condition)
    if @config['show_humidity'] == 'YES' && weather_data[:humidity]
      humidity_val = weather_data[:humidity]
      if humidity_val && humidity_val.is_a?(Numeric)
        output_parts << "#{humidity_val.round}% RH"
      end
    end
    
    output_parts << condition
    
    # Add additional data based on config and F/C mode
    
    # Precipitation
    if @config['show_precipitation'] == 'YES' && weather_data[:precipitation]
      precip_mm = weather_data[:precipitation]
      if precip_mm && precip_mm.is_a?(Numeric)
        # Check if we should show zero precipitation
        show_precip = false
        if precip_mm > 0
          show_precip = true
        elsif @config['show_zero_precip'] == 'YES'
          show_precip = true
        end
        
        # Check trace threshold
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
    
    # Wind
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
        
        # Add direction if available
        if weather_data[:wind_direction] && weather_data[:wind_direction].is_a?(Numeric)
          dir = wind_direction_to_cardinal(weather_data[:wind_direction])
          wind_str += " #{dir}" if dir
        end
        
        # Add gusts if available
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
    
    # Pressure
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
    
    # Exit if display only
    exit 0 if display_only == 'v'
    
    # Write temperature file
    temp_mode = @config['Temperature_mode']
    tmin = temp_mode == 'C' ? -60 : -100
    tmax = temp_mode == 'C' ? 60 : 150
    temp_value = temp_mode == 'C' ? temp_c : temp_f
    
    if temp_value >= tmin && temp_value <= tmax
      begin
        # Round temperature to match display (not truncate)
        File.write(temp_path('temperature'), temp_value.round.to_s)
      rescue => e
        warn("Error writing temperature file: #{e.message}")
      end
    end
    
    # Process weather condition
    if @config['process_condition'] == 'YES' && condition
      process_weather_condition(condition)
    end
  end

  def cleanup_old_files
    [temp_path('temperature'), temp_path('condition.ulaw'), temp_path('timezone')].each do |file|
      if File.exist?(file)
        File.unlink(file) rescue nil
      end
    end
  end

  def process_weather_condition(condition_text)
    return unless Dir.exist?(weather_sound_dir)
    
    condition_lower = condition_text.downcase
    condition_files = []
    
    # Priority order for matching:
    # 1. Try full condition text (with spaces as hyphens, underscores, or removed)
    # 2. Try individual words (preserve original order for multi-word conditions)
    # 3. Try pattern matching
    # 4. Fall back to defaults
    
    # Important weather words (prioritize these over modifiers like "light", "heavy")
    important_words = %w[snow rain thunderstorm hail sleet fog drizzle showers cloudy overcast sunny clear]
    modifiers = %w[light heavy freezing mostly partly]
    
    # Try full condition text variations
    [condition_lower, condition_lower.gsub(/\s+/, '-'), condition_lower.gsub(/\s+/, '_'), condition_lower.gsub(/\s+/, '')].each do |variant|
      file = "#{weather_sound_dir}/#{variant}.ulaw"
      if File.exist?(file)
        condition_files << file
        break
      end
    end
    
    # If no full match, try individual words (preserve original order for multi-word conditions)
    if condition_files.empty?
      words = condition_lower.split(/\s+/).reject(&:empty?)
      words.each do |word|
        file = "#{weather_sound_dir}/#{word}.ulaw"
        if File.exist?(file)
          condition_files << file
        end
      end
    end
    
    # Try pattern matching if still no match
    if condition_files.empty?
      words = condition_lower.split(/\s+/).reject(&:empty?)
      sorted_words = words.sort_by { |w| important_words.include?(w) ? 0 : (modifiers.include?(w) ? 1 : 2) }
      Dir.glob("#{weather_sound_dir}/*.ulaw").each do |file|
        filename = File.basename(file, '.ulaw').downcase
        sorted_words.each do |word|
          if filename == word || (filename.include?(word) && word.length >= 4)
            condition_files << file
            break
          end
        end
        break if condition_files.any?
      end
    end
    
    # Try defaults if no match found
    if condition_files.empty?
      %w[clear sunny fair].find { |d| File.exist?(file = "#{weather_sound_dir}/#{d}.ulaw") && condition_files << file }
    end
    
    # Write condition sound file
    if condition_files.any?
      File.open(temp_path('condition.ulaw'), 'wb') do |out|
        condition_files.each do |file|
          if File.exist?(file)
            File.open(file, 'rb') do |in_file|
              while chunk = in_file.read(HTTP_BUFFER_SIZE)
                out.write(chunk)
              end
            end
          end
        end
      end
    else
      warn("No weather condition sound files found for: #{condition_text}", true)
      warn("  Expected sound directory: #{weather_sound_dir}", true)
      warn("  Hint: Install weather sound files or disable condition announcements", true)
    end
  end

  def parse_ini_file(file_path)
    result = {}
    current_section = nil
    File.readlines(file_path).each do |line|
      line = line.strip
      next if line.empty? || line.start_with?('#', ';')
      if line =~ /^\[(.+)\]$/
        result[current_section = $1] ||= {}
      elsif line =~ /^([^=]+)=(.*)$/ && current_section
        result[current_section][$1.strip] = $2.strip.gsub(/^["']|["']$/, '')
      end
    end
    result
  end
  
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

  def iata_code?(code)
    return false unless code =~ /^[A-Z]{3}$/i
    # IATA codes are 3 uppercase letters
    true
  end

  def refresh_airports_cache_if_stale
    cache = SaytimeWeather::Paths.airports_cache_path
    max_age = SaytimeWeather::Network.airports_cache_max_age
    stale = !File.exist?(cache) || (Time.now - File.mtime(cache)) > max_age
    return unless stale

    body = @http.get(SaytimeWeather::Network.airports_data_url, SaytimeWeather::Network.timeout_long,
                   SaytimeWeather::Endpoints::DEFAULT_HTTP_UA)
    return if body.nil? || body.empty?

    tmp = "#{cache}.part"
    File.write(tmp, body)
    File.rename(tmp, cache)
  rescue => e
    warn("Airports data download failed: #{e.message}") if @options[:verbose]
  end

  def build_airport_iata_map
    refresh_airports_cache_if_stale
    cache = SaytimeWeather::Paths.airports_cache_path
    return {} unless File.exist?(cache)

    map = {}
    CSV.foreach(cache, headers: true) do |row|
      iata = row['iata_code']&.strip&.upcase
      next unless iata && iata.length == 3 && iata.match?(/\A[A-Z]{3}\z/)

      icao = row['icao_code']&.strip&.upcase
      next if icao.nil? || icao.empty?

      map[iata] = icao
    end
    map
  rescue => e
    warn("Failed to parse airports data: #{e.message}") if @options[:verbose]
    {}
  end

  def airport_iata_to_icao_map
    @airport_iata_map ||= build_airport_iata_map
  end

  def iata_to_icao(iata)
    iata = iata.upcase
    icao = airport_iata_to_icao_map[iata]
    return icao if icao && !icao.empty?

    # US and US territories: METAR commonly uses K + IATA when not in registry
    "K#{iata}"
  end

  def icao_code?(code)
    return false unless code =~ /^[A-Z]{4}$/i
    prefix = code[0].upcase
    %w[A B C D E F G H I J K L M N O P Q R S T U V W Y Z].include?(prefix)
  end

  def fetch_metar_weather(icao)
    icao = icao.upcase
    tlong = SaytimeWeather::Network.timeout_long

    metar = @http.get(SaytimeWeather::Endpoints.aviation_metar_url(icao), tlong)
    metar = metar.strip if metar

    unless metar && !metar.empty?
      response = @http.get(SaytimeWeather::Endpoints.noaa_metar_file_url(icao), tlong)
      if response
        lines = response.split("\n")
        metar = lines[1].strip if lines.length > 1
      end
    end
    
    return nil unless metar && !metar.empty?
    
    
    temp_f = parse_metar_temperature(metar)
    condition = parse_metar_condition(metar)
    
    [temp_f, condition]
  end

  def parse_metar_temperature(metar)
    if metar =~ /\s(M?\d{2})\/(M?\d{2})\s/
      temp_c_str = $1
      temp_c_str = temp_c_str.sub(/^M/, '-')
      temp_c_str = temp_c_str.sub(/^(-?)0+(\d)/, '\1\2')
      temp_c = temp_c_str.to_f
      temp_f = (temp_c * 9.0 / 5.0) + 32.0
      temp_f.round
    end
  end

  def parse_metar_condition(metar)
    return 'Thunderstorm' if metar =~ /\bTS\b/
    return 'Heavy Rain' if metar =~ /\+RA\b/
    return 'Rain' if metar =~ /(-|VC)?RA\b/
    return 'Light Rain' if metar =~ /-RA\b/
    return 'Drizzle' if metar =~ /DZ\b/
    return 'Snow' if metar =~ /SN\b/
    return 'Sleet' if metar =~ /PL\b/
    return 'Hail' if metar =~ /GR\b/
    return 'Foggy' if metar =~ /\bFG\b/
    return 'Mist' if metar =~ /BR\b/
    return 'Overcast' if metar =~ /\bOVC\d{3}\b/
    return 'Cloudy' if metar =~ /\bBKN\d{3}\b/
    return 'Partly Cloudy' if metar =~ /\bSCT\d{3}\b/
    return 'Clear' if metar =~ /\b(FEW\d{3}|CLR|SKC)\b/
    'Clear'
  end

  def special_locations_table
    @special_locations_table ||= load_special_locations_json
  end

  def load_special_locations_json
    path = SaytimeWeather::Paths.special_locations_file
    return {} unless File.exist?(path)

    raw = JSON.parse(File.read(path))
    out = {}
    raw.each do |k, v|
      next unless k.is_a?(String) && v.is_a?(Array) && v.length >= 2

      out[k.upcase.gsub(/[^A-Z0-9]/, '')] = [v[0].to_f, v[1].to_f]
    end
    out
  rescue => e
    warn("Failed to load special_locations.json: #{e.message}")
    {}
  end

  def postal_to_coordinates(postal)
    postal_uc = postal.upcase.gsub(/[^A-Z0-9]/, '')
    if (coords = special_locations_table[postal_uc])
      return coords
    end

    ndelay = SaytimeWeather::Network.nominatim_delay
    sleep(ndelay) if ndelay > 0

    url = if postal =~ /^\d{5}$/
            SaytimeWeather::Endpoints.nominatim_postal_url(postal, country: @config['default_country'].downcase)
          elsif postal =~ /^([A-Z]\d[A-Z])\s?\d[A-Z]\d$/i
            normalized = postal.upcase.gsub(/\s+/, '').sub(/^([A-Z]\d[A-Z])(\d[A-Z]\d)$/, '\1 \2')
            SaytimeWeather::Endpoints.nominatim_postal_url(normalized, country: 'ca')
          else
            SaytimeWeather::Endpoints.nominatim_postal_url(postal)
          end

    response = @http.get(url, SaytimeWeather::Network.timeout_short)
    return nil unless response
    
    data = safe_decode_json(response)
    return nil unless data.is_a?(Array) && data.any?
    
    # Safely extract coordinates with validation
    first_result = data[0]
    return nil unless first_result.is_a?(Hash) && first_result['lat'] && first_result['lon']
    
    lat = first_result['lat'].to_f
    lon = first_result['lon'].to_f
    
    # Validate coordinate ranges
    return nil if lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0
    
    [lat, lon]
  end

  def fetch_weather_openmeteo(lat, lon)
    # Validate coordinates
    return nil if lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0
    
    # Build current parameters - include additional data if requested
    current_params = "temperature_2m,weather_code,is_day"
    if @config['show_precipitation'] == 'YES' || @config['show_wind'] == 'YES' || @config['show_pressure'] == 'YES' || @config['show_humidity'] == 'YES'
      current_params += ",precipitation" if @config['show_precipitation'] == 'YES'
      current_params += ",wind_speed_10m,wind_direction_10m,wind_gusts_10m" if @config['show_wind'] == 'YES'
      current_params += ",pressure_msl" if @config['show_pressure'] == 'YES'
      current_params += ",relative_humidity_2m" if @config['show_humidity'] == 'YES'
    end
    
    url = SaytimeWeather::Endpoints.open_meteo_url(lat, lon, current_params)
    response = @http.get(url, SaytimeWeather::Network.timeout_long)
    return nil unless response
    
    data = safe_decode_json(response)
    return nil unless data && data['current']
    
    temp = data['current']['temperature_2m']
    code = data['current']['weather_code']
    is_day = data['current']['is_day'] || 1
    
    # Validate temperature is numeric
    return nil unless temp.is_a?(Numeric)
    
    condition = weather_code_to_text(code, is_day)
    timezone = data['timezone'] || ''
    
    write_timezone_file(timezone)
    
    # Extract additional data
    result = {
      temp: temp,
      condition: condition,
      timezone: timezone,
      precipitation: data['current']['precipitation'],
      wind_speed: data['current']['wind_speed_10m'],
      wind_direction: data['current']['wind_direction_10m'],
      wind_gusts: data['current']['wind_gusts_10m'],
      pressure: data['current']['pressure_msl'],
      humidity: data['current']['relative_humidity_2m']
    }
    
    result
  end

  def write_timezone_file(timezone)
    return unless timezone && !timezone.empty?
    
    begin
      File.write(temp_path('timezone'), timezone)
    rescue => e
      warn("Failed to write timezone file: #{e.message}")
    end
  end

  def weather_code_to_text(code, is_day = 1)
    
    return 'Sunny' if code == 1 && is_day == 1
    return 'Mainly Clear' if code == 1 && is_day == 0
    return 'Mostly Sunny' if code == 2 && is_day == 1
    return 'Partly Cloudy' if code == 2 && is_day == 0
    
    codes = {
      0 => 'Clear',
      3 => 'Overcast',
      45 => 'Foggy',
      48 => 'Foggy',
      51 => 'Light Drizzle',
      53 => 'Drizzle',
      55 => 'Heavy Drizzle',
      56 => 'Light Freezing Drizzle',
      57 => 'Freezing Drizzle',
      61 => 'Light Rain',
      63 => 'Rain',
      65 => 'Heavy Rain',
      66 => 'Light Freezing Rain',
      67 => 'Freezing Rain',
      71 => 'Light Snow',
      73 => 'Snow',
      75 => 'Heavy Snow',
      77 => 'Snow Grains',
      80 => 'Light Showers',
      81 => 'Showers',
      82 => 'Heavy Showers',
      85 => 'Light Snow Showers',
      86 => 'Snow Showers',
      95 => 'Thunderstorm',
      96 => 'Thunderstorm with Light Hail',
      99 => 'Thunderstorm with Hail'
    }
    
    codes[code] || 'Unknown'
  end

  # Unit conversion functions
  def mm_to_inches(mm)
    return nil unless mm && mm.is_a?(Numeric)
    (mm / 25.4).round(2)
  end

  def ms_to_mph(ms)
    return nil unless ms && ms.is_a?(Numeric)
    (ms * 2.23694).round
  end

  def ms_to_kmh(ms)
    return nil unless ms && ms.is_a?(Numeric)
    (ms * 3.6).round
  end

  def hpa_to_inhg(hpa)
    return nil unless hpa && hpa.is_a?(Numeric)
    (hpa * 0.02953).round(2)
  end

  def wind_direction_to_cardinal(degrees)
    return nil unless degrees && degrees.is_a?(Numeric)
    directions = %w[N NNE NE ENE E ESE SE SSE S SSW SW WSW W WNW NW NNW]
    index = ((degrees + 11.25) / 22.5).round % 16
    directions[index]
  end

  def fetch_weather_nws(lat, lon)
    # Validate coordinates are within valid ranges
    return nil if lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0
    
    # Rough US bounds check (NWS only supports US locations)
    if lat < 18.0 || lat > 72.0 || lon < -180.0 || lon > -50.0
      return nil
    end
    
    # Step 1: Get grid points
    # NWS API requires coordinates rounded to 4 decimal places to avoid redirects
    lat_rounded = lat.round(4)
    lon_rounded = lon.round(4)
    points_url = SaytimeWeather::Endpoints.nws_points_url(lat_rounded, lon_rounded)
    nws_ua = SaytimeWeather::Endpoints::NWS_API_UA
    response = @http.get(points_url, SaytimeWeather::Network.timeout_long, nws_ua)
    return nil unless response
    
    points_data = safe_decode_json(response)
    return nil unless points_data && points_data['properties']
    
    timezone = points_data['properties']['timeZone'] || ''
    observation_stations_url = points_data['properties']['observationStations']
    
    # Step 2: Get current observations first (matching Perl version - current conditions, not forecast)
    temp = nil
    condition = nil
    precipitation = nil
    wind_speed = nil
    wind_direction = nil
    wind_gusts = nil
    pressure = nil
    humidity = nil
    
    if observation_stations_url
      # Get list of observation stations
      response = @http.get(observation_stations_url, SaytimeWeather::Network.timeout_long, nws_ua)
      if response
        stations_data = safe_decode_json(response)
        if stations_data && stations_data['features'] && stations_data['features'].any?
          # Try stations in order until we get valid data
          stations_data['features'].each do |station|
            station_id = station['properties']['stationIdentifier']
            next unless station_id
            
            # Get latest observation from this station
            obs_url = SaytimeWeather::Endpoints.nws_station_observation_url(station_id)
            response = @http.get(obs_url, SaytimeWeather::Network.timeout_long, nws_ua)
            next unless response
            
            obs_data = safe_decode_json(response)
            next unless obs_data && obs_data['properties']
            props = obs_data['properties']
            
            # Temperature is in Celsius, convert to Fahrenheit (use current observation)
            temp_c = props['temperature'] && props['temperature']['value']
            if temp_c && temp_c.is_a?(Numeric)
              temp = (temp_c * 9.0 / 5.0) + 32.0
            end
            
            # Get condition from observations (current conditions take priority)
            condition_text = props['textDescription'] || ''
            if condition_text && !condition_text.empty?
              condition = parse_nws_condition(condition_text)
            end
            
            # If still no condition, try icon field as fallback
            if !condition
              icon = props['icon'] || ''
              if icon.include?('skc') || icon.include?('clear')
                condition = 'Clear'
              elsif icon.include?('few')
                condition = 'Clear'
              elsif icon.include?('sct')
                condition = 'Partly Cloudy'
              elsif icon.include?('bkn') || icon.include?('ovc')
                condition = 'Cloudy'
              end
            end
            
            # Extract additional data if requested
            if @config['show_precipitation'] == 'YES'
              # NWS provides precipitation in mm
              precip_mm = props['precipitationLastHour'] && props['precipitationLastHour']['value']
              precipitation = precip_mm if precip_mm && precip_mm.is_a?(Numeric)
            end
            
            if @config['show_wind'] == 'YES'
              # NWS provides wind speed with unitCode - check the unit
              ws_obj = props['windSpeed']
              if ws_obj && ws_obj['value'] && ws_obj['value'].is_a?(Numeric)
                ws_value = ws_obj['value']
                unit_code = (ws_obj['unitCode'] || '').downcase
                
                # Convert to m/s based on unitCode
                # Common NWS unitCodes: "wmoUnit:m_s-1" (m/s), "wmoUnit:km_h-1" (km/h), "wmoUnit:mi_h-1" (mph), "wmoUnit:kt" (knots)
                # Also check for "unit:" prefix variations
                if unit_code.include?('mi_h') || unit_code.include?('mph') || unit_code.include?('mile')
                  # Already in mph, convert to m/s
                  wind_speed = ws_value / 2.23694
                elsif unit_code.include?('km_h') || unit_code.include?('kmh') || unit_code.include?('kilometer')
                  # In km/h, convert to m/s
                  wind_speed = ws_value / 3.6
                elsif unit_code.include?('kt') || unit_code.include?('knot')
                  # In knots, convert to m/s (1 knot = 0.514444 m/s)
                  wind_speed = ws_value * 0.514444
                elsif unit_code.include?('m_s') || unit_code.include?('meter') || unit_code.empty?
                  # Already in m/s, or empty unitCode (default to m/s for NWS)
                  wind_speed = ws_value
                else
                  # Unknown unitCode - default to m/s (most common for NWS)
                  # Log a warning in verbose mode if unitCode is present but unrecognized
                  if @options[:verbose] && !unit_code.empty?
                    warn("Unknown wind speed unitCode: #{ws_obj['unitCode']}, assuming m/s")
                  end
                  wind_speed = ws_value
                end
              end
              
              wd = props['windDirection'] && props['windDirection']['value']
              wind_direction = wd if wd && wd.is_a?(Numeric)
              
              wg_obj = props['windGust']
              if wg_obj && wg_obj['value'] && wg_obj['value'].is_a?(Numeric)
                wg_value = wg_obj['value']
                wg_unit_code = wg_obj['unitCode'] || ''
                
                # Convert gusts to m/s based on unitCode
                if wg_unit_code.include?('mi_h-1') || wg_unit_code.include?('mph')
                  wind_gusts = wg_value / 2.23694
                elsif wg_unit_code.include?('km_h-1') || wg_unit_code.include?('kmh')
                  wind_gusts = wg_value / 3.6
                elsif wg_unit_code.include?('kt') || wg_unit_code.include?('knot')
                  wind_gusts = wg_value * 0.514444
                elsif wg_unit_code.include?('m_s-1') || wg_unit_code.include?('ms')
                  wind_gusts = wg_value
                else
                  wind_gusts = wg_value
                end
              end
            end
            
            if @config['show_pressure'] == 'YES'
              # NWS provides pressure in Pa, convert to hPa
              press_pa = props['seaLevelPressure'] && props['seaLevelPressure']['value']
              if press_pa && press_pa.is_a?(Numeric)
                pressure = press_pa / 100.0  # Convert Pa to hPa
              end
            end
            
            if @config['show_humidity'] == 'YES'
              # NWS provides relative humidity as percentage
              rh = props['relativeHumidity'] && props['relativeHumidity']['value']
              humidity = rh if rh && rh.is_a?(Numeric)
            end
            
            # Stop if we have both temp and condition
            break if temp && condition
          end
        end
      end
    end
    
    # Step 3: Fall back to forecast ONLY if current observations not available
    # Use forecast only if observations didn't provide both temp and condition
    unless temp && condition
      forecast_url = points_data['properties']['forecast']
      if forecast_url
        response = @http.get(forecast_url, SaytimeWeather::Network.timeout_long, nws_ua)
        if response
          forecast_data = safe_decode_json(response)
          if forecast_data && forecast_data['properties']
            periods = forecast_data['properties']['periods']
            if periods && periods.any?
              # Use first period as fallback only
              current = periods[0]
              if current
                # Validate temperature is numeric before using
                forecast_temp = current['temperature']
                if !temp && forecast_temp && forecast_temp.is_a?(Numeric)
                  temp = forecast_temp
                end
                condition_text = current['shortForecast'] || current['detailedForecast'] || ''
                if condition_text && !condition_text.empty? && !condition
                  condition = parse_nws_condition(condition_text)
                end
              end
            end
          end
        end
      end
    end
    
    return nil unless temp && condition
    
    write_timezone_file(timezone)
    
    {
      temp: temp,
      condition: condition,
      timezone: timezone,
      precipitation: precipitation,
      wind_speed: wind_speed,
      wind_direction: wind_direction,
      wind_gusts: wind_gusts,
      pressure: pressure,
      humidity: humidity
    }
  end

  def parse_nws_condition(text)
    text = text.downcase
    return 'Thunderstorm' if text =~ /thunderstorm|thunder|t-storm/
    return 'Heavy Rain' if text =~ /heavy.*rain|rain.*heavy|torrential/
    return 'Heavy Snow' if text =~ /heavy.*snow|snow.*heavy/
    return 'Light Rain' if text =~ /light.*rain|rain.*light|drizzle/
    return 'Light Snow' if text =~ /light.*snow|snow.*light|flurries/
    return 'Rain' if text =~ /\brain\b/
    return 'Snow' if text =~ /\bsnow\b/
    return 'Sleet' if text =~ /sleet|freezing.*rain|ice.*pellets/
    return 'Hail' if text =~ /\bhail\b/
    return 'Foggy' if text =~ /\bfog\b|\bmist\b/
    return 'Overcast' if text =~ /overcast|cloudy.*cloudy/
    return 'Cloudy' if text =~ /\bcloudy\b/
    return 'Partly Cloudy' if text =~ /partly.*cloud|partly.*sun|mostly.*cloud/
    return 'Mostly Sunny' if text =~ /mostly.*sun|mostly.*clear/
    # Check for "Sunny" before "Clear" to match Perl version
    return 'Sunny' if text =~ /\bsunny\b|clear.*sun|sun.*clear/
    return 'Clear' if text =~ /\bclear\b/
    'Clear'
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  script = WeatherScript.new
  script.run
end

