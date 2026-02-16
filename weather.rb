#!/usr/bin/env ruby
# frozen_string_literal: true

# weather.rb - Weather retrieval script for saytime-weather (Ruby version)
# Copyright 2026 Jory A. Pratt, W5GLE
#
# - Fetches weather from Open-Meteo or NWS APIs (free, no API keys)
# - Supports postal codes, IATA airport codes, ICAO airport codes, and special locations
# - Creates sound files for temperature and conditions

require 'net/http'
require 'uri'
require 'json'
require 'optparse'
require 'tempfile'

VERSION = '0.0.6'
TMP_DIR = '/tmp'
TEMP_FILE = '/tmp/temperature'
COND_FILE = '/tmp/condition.ulaw'
TIMEZONE_FILE = '/tmp/timezone'
WEATHER_SOUND_DIR = '/usr/share/asterisk/sounds/en/wx'

CONFIG_PATH = '/etc/asterisk/local/weather.ini'

HTTP_TIMEOUT_SHORT = 10
HTTP_TIMEOUT_LONG = 15
HTTP_BUFFER_SIZE = 8192
NOMINATIM_DELAY = 1

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
    parse_options
    load_config
  end

  def parse_options
    parser = OptionParser.new do |opts|
      opts.banner = "weather.rb version #{VERSION}\n\nUsage: #{File.basename($PROGRAM_NAME)} [OPTIONS] location_id [v]\n\n"
      
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
        puts "weather.rb version #{VERSION}"
        exit 0
      end
    end
    
    parser.parse!
  end

  def show_usage
    puts "weather.rb version #{VERSION}\n\n"
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
    puts "  #{CONFIG_PATH}\n\n"
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
    puts "  - precip_trace_mm: decimal (default: 0.10) - Minimum mm to show precipitation\n\n"
    puts "Note: Command line options override configuration file settings for that run.\n"
  end

  def load_config
    config_path = @options[:config_file] || CONFIG_PATH
    
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
        File.write(TEMP_FILE, temp_value.round.to_s)
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
    [TEMP_FILE, COND_FILE, TIMEZONE_FILE].each do |file|
      if File.exist?(file)
        File.unlink(file) rescue nil
      end
    end
  end

  def process_weather_condition(condition_text)
    return unless Dir.exist?(WEATHER_SOUND_DIR)
    
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
      file = "#{WEATHER_SOUND_DIR}/#{variant}.ulaw"
      if File.exist?(file)
        condition_files << file
        break
      end
    end
    
    # If no full match, try individual words (preserve original order for multi-word conditions)
    if condition_files.empty?
      words = condition_lower.split(/\s+/).reject(&:empty?)
      words.each do |word|
        file = "#{WEATHER_SOUND_DIR}/#{word}.ulaw"
        if File.exist?(file)
          condition_files << file
        end
      end
    end
    
    # Try pattern matching if still no match
    if condition_files.empty?
      words = condition_lower.split(/\s+/).reject(&:empty?)
      sorted_words = words.sort_by { |w| important_words.include?(w) ? 0 : (modifiers.include?(w) ? 1 : 2) }
      Dir.glob("#{WEATHER_SOUND_DIR}/*.ulaw").each do |file|
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
      %w[clear sunny fair].find { |d| File.exist?(file = "#{WEATHER_SOUND_DIR}/#{d}.ulaw") && condition_files << file }
    end
    
    # Write condition sound file
    if condition_files.any?
      File.open(COND_FILE, 'wb') do |out|
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
      warn("  Expected sound directory: #{WEATHER_SOUND_DIR}", true)
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

  def http_get(url, timeout = HTTP_TIMEOUT_SHORT, user_agent = nil, max_redirects = 5)
    return nil if max_redirects <= 0
    
    begin
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = timeout
      http.read_timeout = timeout
      
      request = Net::HTTP::Get.new(uri)
      request['User-Agent'] = user_agent || 'Mozilla/5.0 (compatible; WeatherBot/1.0)'
      
      response = http.request(request)
      response_code = response.code.to_i
      
      case response_code
      when 200
        response.body
      when 301, 302, 303, 307, 308
        # Handle redirects
        location = response['Location'] || response['location']
        if location
          # Use URI to properly resolve relative URLs
          begin
            redirect_uri = URI(location)
            if redirect_uri.relative?
              redirect_uri = uri + redirect_uri
            end
            redirect_url = redirect_uri.to_s
            return http_get(redirect_url, timeout, user_agent, max_redirects - 1)
          rescue => e
            warn("Failed to follow redirect: #{e.message}") if @options[:verbose]
          end
        end
        nil
      when 429
        # Rate limited
        warn("Rate limited by server, please wait before retrying") if @options[:verbose]
        nil
      when 404
        # Not found
        nil
      else
        warn("HTTP error #{response_code} from #{uri.host}") if @options[:verbose]
        nil
      end
    rescue URI::InvalidURIError => e
      warn("Invalid URL: #{url}") if @options[:verbose]
      nil
    rescue Net::TimeoutError => e
      warn("Request timeout for #{url}") if @options[:verbose]
      nil
    rescue => e
      warn("HTTP request failed: #{e.message}") if @options[:verbose]
      nil
    end
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

  def iata_to_icao(iata)
    iata = iata.upcase
    
    # US airports: ICAO is typically K + IATA
    # Try this first for US airports
    us_icao = "K#{iata}"
    
    # International IATA to ICAO mapping for common airports
    # This covers major international airports that don't follow the K+IATA pattern
    iata_to_icao_map = {
      # Major European airports
      'LHR' => 'EGLL',  # London Heathrow
      'LGW' => 'EGKK',  # London Gatwick
      'CDG' => 'LFPG',  # Paris Charles de Gaulle
      'ORY' => 'LFPO',  # Paris Orly
      'FRA' => 'EDDF',  # Frankfurt
      'MUC' => 'EDDM',  # Munich
      'AMS' => 'EHAM',  # Amsterdam
      'BRU' => 'EBBR',  # Brussels
      'ZUR' => 'LSZH',  # Zurich
      'VIE' => 'LOWW',  # Vienna
      'MAD' => 'LEMD',  # Madrid
      'BCN' => 'LEBL',  # Barcelona
      'FCO' => 'LIRF',  # Rome Fiumicino
      'MXP' => 'LIMC',  # Milan Malpensa
      'ATH' => 'LGAV',  # Athens
      'DUB' => 'EIDW',  # Dublin
      'CPH' => 'EKCH',  # Copenhagen
      'ARN' => 'ESSA',  # Stockholm
      'OSL' => 'ENGM',  # Oslo
      'HEL' => 'EFHK',  # Helsinki
      'WAW' => 'EPWA',  # Warsaw
      'PRG' => 'LKPR',  # Prague
      'BUD' => 'LHBP',  # Budapest
      'IST' => 'LTFM',  # Istanbul
      'DXB' => 'OMDB',  # Dubai
      'DOH' => 'OTHH',  # Doha
      'AUH' => 'OMAA',  # Abu Dhabi
      'JED' => 'OEJN',  # Jeddah
      'RUH' => 'OERK',  # Riyadh
      # Major Asian airports
      'NRT' => 'RJAA',  # Tokyo Narita
      'HND' => 'RJTT',  # Tokyo Haneda
      'ICN' => 'RKSI',  # Seoul Incheon
      'PEK' => 'ZBAA',  # Beijing
      'PVG' => 'ZSPD',  # Shanghai Pudong
      'CAN' => 'ZGGG',  # Guangzhou
      'SZX' => 'ZGSZ',  # Shenzhen
      'HKG' => 'VHHH',  # Hong Kong
      'TPE' => 'RCTP',  # Taipei
      'SIN' => 'WSSS',  # Singapore
      'BKK' => 'VTBS',  # Bangkok
      'KUL' => 'WMKK',  # Kuala Lumpur
      'CGK' => 'WIII',  # Jakarta
      'MNL' => 'RPLL',  # Manila
      'DEL' => 'VIDP',  # Delhi
      'BOM' => 'VABB',  # Mumbai
      'CCU' => 'VECC',  # Kolkata
      'BLR' => 'VOBL',  # Bangalore
      # Major Australian/New Zealand airports
      'SYD' => 'YSSY',  # Sydney
      'MEL' => 'YMML',  # Melbourne
      'BNE' => 'YBBN',  # Brisbane
      'PER' => 'YPPH',  # Perth
      'ADL' => 'YPAD',  # Adelaide
      'AKL' => 'NZAA',  # Auckland
      'WLG' => 'NZWN',  # Wellington
      'CHC' => 'NZCH',  # Christchurch
      # Major Canadian airports
      'YYZ' => 'CYYZ',  # Toronto Pearson
      'YVR' => 'CYVR',  # Vancouver
      'YUL' => 'CYUL',  # Montreal
      'YYC' => 'CYYC',  # Calgary
      'YEG' => 'CYEG',  # Edmonton
      'YOW' => 'CYOW',  # Ottawa
      'YHZ' => 'CYHZ',  # Halifax
      'YWG' => 'CYWG',  # Winnipeg
      # Major Latin American airports
      'MEX' => 'MMMX',  # Mexico City
      'GDL' => 'MMGL',  # Guadalajara
      'CUN' => 'MMUN',  # Cancun
      'GRU' => 'SBGR',  # São Paulo
      'GIG' => 'SBGL',  # Rio de Janeiro
      'EZE' => 'SAEZ',  # Buenos Aires
      'SCL' => 'SCEL',  # Santiago
      'LIM' => 'SPIM',  # Lima
      'BOG' => 'SKBO',  # Bogotá
      # Major African airports
      'JNB' => 'FAOR',  # Johannesburg
      'CPT' => 'FACT',  # Cape Town
      'CAI' => 'HECA',  # Cairo
      'NBO' => 'HKJK',  # Nairobi
      'LOS' => 'DNMM',  # Lagos
      'ADD' => 'HAAB',  # Addis Ababa
    }
    
    # Check lookup table first
    return iata_to_icao_map[iata] if iata_to_icao_map[iata]
    
    # For US airports, try K + IATA
    # We'll validate this by trying to fetch METAR data
    us_icao
  end

  def icao_code?(code)
    return false unless code =~ /^[A-Z]{4}$/i
    prefix = code[0].upcase
    %w[A B C D E F G H I J K L M N O P Q R S T U V W Y Z].include?(prefix)
  end

  def fetch_metar_weather(icao)
    icao = icao.upcase
    
    # Try NOAA Aviation Weather API
    url = "https://aviationweather.gov/api/data/metar?ids=#{URI.encode_www_form_component(icao)}&format=raw&hours=0&taf=false"
    metar = http_get(url, HTTP_TIMEOUT_LONG)
    metar = metar.strip if metar
    
    # Fallback to NWS
    unless metar && !metar.empty?
      url = "https://tgftp.nws.noaa.gov/data/observations/metar/stations/#{icao}.TXT"
      response = http_get(url, HTTP_TIMEOUT_LONG)
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

  def postal_to_coordinates(postal)
    # Special locations (Antarctica, Arctic, remote islands, DXpedition sites)
    special_locations = {
      # Antarctica
      'SOUTHPOLE' => [-90.0, 0.0],
      'MCMURDO' => [-77.85, 166.67],
      'PALMER' => [-64.77, -64.05],
      'VOSTOK' => [-78.46, 106.84],
      'CASEY' => [-66.28, 110.53],
      'MAWSON' => [-67.60, 62.87],
      'DAVIS' => [-68.58, 77.97],
      'SCOTTBASE' => [-77.85, 166.76],
      'SYOWA' => [-69.00, 39.58],
      'CONCORDIA' => [-75.10, 123.33],
      'HALLEY' => [-75.58, -26.66],
      'DUMONT' => [-66.66, 140.01],
      'SANAE' => [-71.67, -2.84],
      # Arctic
      'ALERT' => [82.50, -62.35],
      'EUREKA' => [79.99, -85.93],
      'THULE' => [76.53, -68.70],
      'LONGYEARBYEN' => [78.22, 15.65],
      'BARROW' => [71.29, -156.79],
      'RESOLUTE' => [74.72, -94.83],
      'GRISE' => [76.42, -82.90],
      # Remote Islands (DXpedition Sites)
      'ASCENSION' => [-7.95, -14.36],
      'STHELENA' => [-15.97, -5.72],
      'TRISTAN' => [-37.11, -12.28],
      'BOUVET' => [-54.42, 3.38],
      'HEARD' => [-53.10, 73.51],
      'KERGUELEN' => [-49.35, 70.22],
      'CROZET' => [-46.43, 51.86],
      'AMSTERDAM' => [-37.83, 77.57],
      'MACQUARIE' => [-54.62, 158.86],
      # Pacific Islands
      'MIDWAY' => [28.21, -177.38],
      'WAKE' => [19.28, 166.65],
      'JOHNSTON' => [16.73, -169.53],
      'PALMYRA' => [5.89, -162.08],
      'JARVIS' => [-0.37, -159.99],
      'HOWLAND' => [0.81, -176.62],
      'BAKER' => [0.19, -176.48],
      'KINGMAN' => [6.38, -162.42],
      # Indian Ocean
      'DIEGO' => [-7.26, 72.40],
      'CHAGOS' => [-7.26, 72.40],
      'COCOS' => [-12.19, 96.83],
      'CHRISTMAS' => [-10.49, 105.62],
      # South Atlantic
      'FALKLANDS' => [-51.70, -59.52],
      'SOUTHGEORGIA' => [-54.28, -36.51],
      'SOUTHSANDWICH' => [-59.43, -26.35],
      # Pacific Polynesia
      'MARQUESAS' => [-9.00, -140.00],
      'EASTER' => [-27.11, -109.36],
      'PITCAIRN' => [-25.07, -130.10],
      'CLIPPERTON' => [10.30, -109.22],
      'GALAPAGOS' => [-0.95, -90.97],
      # Mountain Observatories
      'MAUNA' => [19.54, -155.58],
      'JUNGFRAUJOCH' => [46.55, 7.98],
      # Extreme Deserts
      'MCMURDODRY' => [-77.85, 163.00],
      'ATACAMA' => [-24.50, -69.25],
      # Other Notable Remote Locations
      'GOUGH' => [-40.35, -9.88],
      'MARION' => [-46.88, 37.86],
      'PRINCE' => [-46.77, 37.86],
      'CAMPBELL' => [-52.55, 169.15],
      'AUCKLAND' => [-50.73, 166.09],
      'KERMADEC' => [-29.25, -177.92],
      'CHATHAM' => [-43.95, -176.55]
    }
    
    postal_uc = postal.upcase.gsub(/[^A-Z0-9]/, '')
    
    if special_locations[postal_uc]
      lat, lon = special_locations[postal_uc]
      return [lat, lon]
    end
    
    # Use Nominatim for regular postal codes
    # Respect Nominatim rate limits (1 request per second recommended)
    sleep(NOMINATIM_DELAY) if NOMINATIM_DELAY > 0
    
    country = ''
    url = nil
    
    if postal =~ /^\d{5}$/
      country = @config['default_country'].downcase
      url = "https://nominatim.openstreetmap.org/search?postalcode=#{URI.encode_www_form_component(postal)}&country=#{country}&format=json&limit=1"
    elsif postal =~ /^([A-Z]\d[A-Z])\s?\d[A-Z]\d$/i
      country = 'ca'
      normalized = postal.upcase.gsub(/\s+/, '').sub(/^([A-Z]\d[A-Z])(\d[A-Z]\d)$/, '\1 \2')
      url = "https://nominatim.openstreetmap.org/search?postalcode=#{URI.encode_www_form_component(normalized)}&country=#{country}&format=json&limit=1"
    else
      url = "https://nominatim.openstreetmap.org/search?postalcode=#{URI.encode_www_form_component(postal)}&format=json&limit=1"
    end
    
    response = http_get(url, HTTP_TIMEOUT_SHORT)
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
    
    url = "https://api.open-meteo.com/v1/forecast?" +
          "latitude=#{lat}&longitude=#{lon}&" +
          "current=#{current_params}&" +
          "temperature_unit=fahrenheit&wind_speed_unit=ms&precipitation_unit=mm&timezone=auto"
    
    response = http_get(url, HTTP_TIMEOUT_LONG)
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
      File.write(TIMEZONE_FILE, timezone)
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
    points_url = "https://api.weather.gov/points/#{lat_rounded},#{lon_rounded}"
    
    response = http_get(points_url, HTTP_TIMEOUT_LONG, 'WeatherBot/1.0 (saytime-weather@github.com)')
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
      response = http_get(observation_stations_url, HTTP_TIMEOUT_LONG, 'WeatherBot/1.0 (saytime-weather@github.com)')
      if response
        stations_data = safe_decode_json(response)
        if stations_data && stations_data['features'] && stations_data['features'].any?
          # Try stations in order until we get valid data
          stations_data['features'].each do |station|
            station_id = station['properties']['stationIdentifier']
            next unless station_id
            
            # Get latest observation from this station
            obs_url = "https://api.weather.gov/stations/#{station_id}/observations/latest"
            response = http_get(obs_url, HTTP_TIMEOUT_LONG, 'WeatherBot/1.0 (saytime-weather@github.com)')
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
        response = http_get(forecast_url, HTTP_TIMEOUT_LONG, 'WeatherBot/1.0 (saytime-weather@github.com)')
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

