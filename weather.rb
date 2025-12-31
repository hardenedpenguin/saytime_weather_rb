#!/usr/bin/env ruby
# frozen_string_literal: true

# weather.rb - Weather retrieval script for saytime-weather (Ruby version)
# Copyright 2026 Jory A. Pratt, W5GLE
#
# - Fetches weather from Open-Meteo or NWS APIs (free, no API keys)
# - Supports postal codes, ICAO airport codes, and special locations
# - Creates sound files for temperature and conditions

require 'net/http'
require 'uri'
require 'json'
require 'optparse'
require 'tempfile'

VERSION = '0.0.1'
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
    puts "  location_id    Postal code, ZIP code, or ICAO airport code"
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
    puts "  ICAO Airport Codes:"
    puts "    #{File.basename($PROGRAM_NAME)} KJFK v                   # JFK Airport, New York"
    puts "    #{File.basename($PROGRAM_NAME)} EGLL                     # Heathrow, London"
    puts "    #{File.basename($PROGRAM_NAME)} CYYZ v                   # Toronto Pearson\n\n"
    puts "Configuration File:"
    puts "  #{CONFIG_PATH}\n\n"
    puts "Configuration Options:"
    puts "  - Temperature_mode: F/C (set to C for Celsius, F for Fahrenheit)"
    puts "  - process_condition: YES/NO (default: YES)"
    puts "  - default_country: ISO country code for postal lookups (default: us)"
    puts "  - weather_provider: openmeteo (worldwide) or nws (US only, default: openmeteo)\n\n"
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
    
    # Apply command line overrides
    @config['default_country'] = @options[:default_country] if @options[:default_country]
    @config['Temperature_mode'] = @options[:temperature_mode] if @options[:temperature_mode]
    @config['process_condition'] = 'NO' if @options[:no_condition]
    
    validate_config
  end

  def create_default_config(config_path)
    
    FileUtils.mkdir_p(File.dirname(config_path)) unless Dir.exist?(File.dirname(config_path))
    File.write(config_path, "[weather]\nTemperature_mode = F\nprocess_condition = YES\ndefault_country = us\nweather_provider = openmeteo\n")
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
    unless temperature && condition
      lat = nil
      lon = nil
      
      # Try ICAO/METAR first
      if icao_code?(location)
        metar_temp, metar_cond = fetch_metar_weather(location)
        
        if metar_temp && metar_cond
          temperature = metar_temp.round.to_s
          condition = metar_cond
          w_type = 'metar'
          
          
        else
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
          if !@provider_explicitly_set && is_us_location
            # Provider not explicitly set and this is a US location - try NWS first (matches Perl behavior)
            temp, cond, tz = fetch_weather_nws(lat, lon)
            if temp && cond
              provider = 'nws'
              w_type = 'nws'
            else
              temp, cond, tz = fetch_weather_openmeteo(lat, lon)
              provider = 'openmeteo'
            end
          elsif provider == 'nws'
            temp, cond, tz = fetch_weather_nws(lat, lon)
            
            unless temp && cond
              temp, cond, tz = fetch_weather_openmeteo(lat, lon)
              provider = 'openmeteo'
            else
              w_type = 'nws'
            end
          else
            temp, cond, tz = fetch_weather_openmeteo(lat, lon)
            provider = 'openmeteo'
          end
          
          if temp && cond
            # Don't round temperature here - keep as float for display, round only for file output
            temperature = temp.to_s
            condition = cond
            timezone = tz
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
          error("  For ICAO codes, ensure the airport code is valid (e.g., KJFK, EGLL)")
        end
        
        w_type = 'openmeteo' unless w_type
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
    temp_c = ((5.0 / 9.0) * (temp_f - 32)).round
    
    # Round temperature to whole number for display
    temp_f_display = temp_f.round
    puts "#{temp_f_display}°F, #{temp_c}°C / #{condition}"
    
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
    # 2. Try individual words, prioritizing important weather words
    # 3. Try pattern matching
    # 4. Fall back to defaults
    
    # Important weather words (prioritize these over modifiers like "light", "heavy")
    important_words = %w[snow rain thunderstorm hail sleet fog drizzle showers cloudy overcast]
    modifiers = %w[light heavy freezing]
    
    # Try full condition text variations
    [condition_lower, condition_lower.gsub(/\s+/, '-'), condition_lower.gsub(/\s+/, '_'), condition_lower.gsub(/\s+/, '')].each do |variant|
      file = "#{WEATHER_SOUND_DIR}/#{variant}.ulaw"
      if File.exist?(file)
        condition_files << file
        break
      end
    end
    
    # If no full match, try individual words (prioritize important words)
    if condition_files.empty?
      words = condition_lower.split(/\s+/).reject(&:empty?)
      sorted_words = words.sort_by { |w| important_words.include?(w) ? 0 : (modifiers.include?(w) ? 1 : 2) }
      sorted_words.each do |word|
        file = "#{WEATHER_SOUND_DIR}/#{word}.ulaw"
        if File.exist?(file)
          condition_files << file
          break
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
          File.open(file, 'rb') { |in_file| out.write(in_file.read) } if File.exist?(file)
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
        end
      end
      nil
    else
      nil
    end
  rescue => e
    nil
  end

  def safe_decode_json(content)
    JSON.parse(content)
  rescue => e
    nil
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
    
    lat = data[0]['lat'].to_f
    lon = data[0]['lon'].to_f
    display = data[0]['display_name'] || postal
    
    
    [lat, lon]
  end

  def fetch_weather_openmeteo(lat, lon)
    
    url = "https://api.open-meteo.com/v1/forecast?" +
          "latitude=#{lat}&longitude=#{lon}&" +
          "current=temperature_2m,weather_code,is_day&" +
          "temperature_unit=fahrenheit&timezone=auto"
    
    response = http_get(url, HTTP_TIMEOUT_LONG)
    return nil unless response
    
    data = safe_decode_json(response)
    return nil unless data && data['current']
    
    temp = data['current']['temperature_2m']
    code = data['current']['weather_code']
    is_day = data['current']['is_day'] || 1
    condition = weather_code_to_text(code, is_day)
    timezone = data['timezone'] || ''
    
    if timezone && !timezone.empty?
      begin
        File.write(TIMEZONE_FILE, timezone)
      rescue => e
        warn("Failed to write timezone file: #{e.message}")
      end
    end
    
    [temp, condition, timezone]
  end

  def weather_code_to_text(code, is_day = 1)
    is_day = 1 unless is_day
    
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

  def fetch_weather_nws(lat, lon)
    # Rough US bounds check
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
            
            # Temperature is in Celsius, convert to Fahrenheit (use current observation)
            temp_c = obs_data['properties']['temperature'] && obs_data['properties']['temperature']['value']
            if temp_c
              temp = (temp_c * 9.0 / 5.0) + 32.0
            end
            
            # Get condition from observations (current conditions take priority)
            condition_text = obs_data['properties']['textDescription'] || ''
            if condition_text && !condition_text.empty?
              condition = parse_nws_condition(condition_text)
            end
            
            # If still no condition, try icon field as fallback
            if !condition
              icon = obs_data['properties']['icon'] || ''
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
                temp = current['temperature'] if !temp
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
    
    if timezone && !timezone.empty?
      begin
        File.write(TIMEZONE_FILE, timezone)
      rescue => e
        warn("Failed to write timezone file: #{e.message}")
      end
    end
    
    [temp, condition, timezone]
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

