# frozen_string_literal: true

require 'json'
require 'optparse'
require 'fileutils'
require_relative 'weather_runner'

module SaytimeWeather
  class WeatherScript
    include WeatherHelpers
    include WeatherConfig
    include WeatherUnits
    include WeatherGeocoding
    include WeatherAirports
    include WeatherMetar
    include WeatherOpenMeteo
    include WeatherNws
    include WeatherMetNo
    include WeatherWttr
    include Weather7Timer
    include WeatherWeatherapi
    include WeatherSound
    include WeatherOptionalFields
    include WeatherProviders
    include WeatherGps
    include WeatherNumeric
    include WeatherValues

    attr_reader :options, :config

    def initialize(options: nil)
      @options = {
        verbose: false,
        config_file: nil,
        default_country: nil,
        temperature_mode: nil,
        no_condition: false,
        use_gps: false,
        custom_sound_dir: nil
      }
      @config = {}
      @provider_explicitly_set = false
      @airport_iata_map = nil
      @airport_icao_coords = nil
      @explicit_location = false

      if options
        merge_runtime_options(options)
      else
        @cli_mode = true
        parse_options
      end

      @http = HttpClient.new(warn_proc: ->(m) { warn(m) }, verbose: @options[:verbose])
      load_config
    end

    def merge_runtime_options(opts)
      SaytimeWeather.normalize_weather_options(opts).each do |key, val|
        @options[key] = key == :temperature_mode ? val.to_s.upcase : val
      end
    end

    def parse_options
      option_parser.parse!
    end

    # Single definition of the CLI options; --help output is generated from it.
    def option_parser
      @option_parser ||= OptionParser.new do |opts|
        opts.banner = "weather.rb version #{VERSION}\n\nUsage: weather.rb [OPTIONS] [location_id] [v]"
        opts.separator ''
        opts.separator 'Arguments:'
        opts.separator '  location_id    Postal code, IATA, ICAO, lat,lon coordinates, or omit with --gps'
        opts.separator '  v              Display text only (no sound output); place after location (see examples)'
        opts.separator ''
        opts.separator 'Examples:'
        opts.separator '  weather.rb 77511 v              # display only'
        opts.separator '  weather.rb -v 77511 v           # verbose display only'
        opts.separator '  weather.rb --gps v              # GPS display only'
        opts.separator ''
        opts.separator 'Options:'
        opts.summary_width = 24
        opts.summary_indent = '  '

        opts.on('-c', '--config FILE', 'Alternate configuration file') { |f| @options[:config_file] = f }
        opts.on('-d', '--default-country CC', 'Override default country') { |cc| @options[:default_country] = cc }
        opts.on('-t', '--temperature-mode M', 'Temperature mode (F or C)') { |m| @options[:temperature_mode] = m.upcase }
        opts.on('--no-condition', 'Skip condition sound files') { @options[:no_condition] = true }
        opts.on('--gps', 'Use GPS via gpsd (see location_source = gps in weather.ini)') { @options[:use_gps] = true }
        opts.on('-v', '--verbose', 'Verbose output') { @options[:verbose] = true }
        opts.on('-h', '--help', 'This help') { show_usage; exit 0 }
        opts.on('--version', 'Version information') { puts "weather.rb version #{VERSION}"; exit 0 }

        opts.separator ''
        opts.separator "Configuration: #{Paths.config_path}"
        opts.separator 'GPS: set location_source = gps in weather.ini or pass --gps. Requires gpsd.'
        opts.separator 'Note: show_* adds text output; announce_* adds radio audio (requires wx sound files).'
        opts.separator 'Generate optional wx sounds with scripts/generate_wx_extra_sounds.sh (asl-tts on ASL node).'
        opts.separator 'Airport METAR: temp/condition from METAR; extras from Open-Meteo when enabled.'
      end
    end

    def show_usage
      puts option_parser.help
    end

  # Returns true on success, false on failure (does not exit).
  def run(location: nil, display_only: nil)
      @owns_run_context = !SaytimeWeather::RunContext.active?
      SaytimeWeather::RunContext.ensure_run!
      SaytimeWeather::RunContext.clear_legacy_scratch! if @owns_run_context
      @http.verbose = @options[:verbose]
      display_only ||= cli_display_only_arg

      if gps_location_enabled?
        loc = location.to_s.strip
        location = loc.empty? ? nil : loc
      else
        location = (location || ARGV[0]).to_s
        if location.empty?
          show_usage
          return :usage
        end
        location = location.strip
      end

      @explicit_location = !location.to_s.strip.empty?

      unless valid_location_format?(location)
        error("Invalid location format.")
        error("  Provided: #{location}")
        error("  Use postal code, airport code, lat,lon coordinates, or --gps")
        return false
      end

      cleanup_old_files

      temperature, condition, provider = fetch_weather_for_location(location)

      temp_f = temperature.to_f
      unless WeatherNumeric.numeric_temp?(temp_f) && WeatherNumeric.valid_condition?(condition)
        label = location_label_for_error(location)
        error("No weather report available")
        error("  Location: #{label}")
        error("  Hint: Check that the location is valid and weather services are accessible")
        return false
      end

      unless temp_f >= -150.0 && temp_f <= 200.0
        error("Invalid temperature value: #{temp_f}°F")
        error("  Location: #{location_label_for_error(location)}")
        return false
      end

      temp_c = ((5.0 / 9.0) * (temp_f - 32)).round
      puts build_output_line(temp_f.round, temp_c, condition)

      return true if display_only == 'v'

      unless write_temperature_file(temp_f, temp_c)
        error('Temperature out of display range; sound file not written')
        error("  Location: #{location_label_for_error(location)}")
        return false
      end

      process_weather_condition(condition) if @config['process_condition'] == 'YES' && condition
      write_weather_extras_file if extra_weather_announce_enabled?
      true
    ensure
      @http.close if @http
      SaytimeWeather::RunContext.cleanup! if @owns_run_context
    end

    private

    # Trailing `v` (display only) from the command line. Only honored when weather.rb is
    # the entry point (not when saytime.rb runs weather in-process), regardless of how
    # the script path appears in $PROGRAM_NAME (/usr/sbin/weather.rb, ./weather.rb, ...).
    def cli_display_only_arg
      return nil unless @cli_mode

      args = gps_location_enabled? ? ARGV : ARGV.drop(1)
      args.include?('v') ? 'v' : nil
    end

    def fetch_weather_for_location(location)
      @weather_data = {}
      @resolved_metar = nil

      if (direct = try_weatherapi_direct_location(location))
        return direct
      end

      if (metar = try_metar_resolution(location))
        return metar
      end

      lat, lon, label = resolve_location_coordinates(location)
      if lat && lon
        weather_data, provider = fetch_coordinate_weather(lat, lon, label)
        if weather_data && valid_weather_data?(weather_data)
          @weather_data = weather_data
          return [weather_data[:temp].to_s, weather_data[:condition], provider]
        end

        report_coordinate_failure(label, lat, lon, provider)
        return [nil, nil, provider]
      end

      report_location_resolution_failure(location, label)
      [nil, nil, nil]
    end

    def resolve_location_coordinates(location)
      if gps_location_enabled?
        fix = read_gps_fix
        if fix
          return [fix[:lat], fix[:lon], format_gps_label(fix)]
        end

        fallback = @config['gps_fallback_location'].to_s.strip
        unless fallback.empty?
          warn("GPS fix unavailable, using fallback location: #{fallback}") if @options[:verbose]
          return resolve_postal_or_airport_coordinates(fallback)
        end

        return [nil, nil, 'gps']
      end

      return [nil, nil, nil] if location.nil? || location.to_s.empty?

      resolve_postal_or_airport_coordinates(location)
    end

    def resolve_postal_or_airport_coordinates(location)
      location = location.to_s.strip

      if coordinate_literal?(location)
        coords = parse_coordinate_literal(location)
        return [coords[0], coords[1], location] if coords
        return [nil, nil, location]
      end

      lat, lon = postal_to_coordinates(location)
      return [lat, lon, location] if lat && lon

      [nil, nil, location]
    end

    def try_weatherapi_direct_location(location)
      return nil unless weatherapi_direct_lookup?
      return nil if gps_location_enabled?
      return nil if location.nil? || location.to_s.empty?
      return nil if coordinate_literal?(location)

      q = weatherapi_query_for_location(location)
      return nil unless q

      if @options[:verbose]
        warn("WeatherAPI direct lookup for #{location} (q=#{q})")
      end

      data = fetch_weather_weatherapi(query: q)
      return nil unless valid_weather_data?(data)

      data = normalize_condition(data)
      lat = data[:lat]
      lon = data[:lon]
      if lat.is_a?(Numeric) && lon.is_a?(Numeric)
        ensure_location_timezone(lat, lon, data)
      elsif data[:timezone] && !data[:timezone].to_s.empty?
        write_timezone_file(data[:timezone])
      end

      @weather_data = data
      if @options[:verbose]
        warn('Weather from WEATHERAPI (direct location lookup)')
      end
      [data[:temp].to_s, data[:condition], 'weatherapi']
    end

    def try_metar_resolution(location)
      return nil if weatherapi_direct_lookup?
      return nil if gps_location_enabled?
      return nil if location.nil? || location.to_s.empty?
      return nil if coordinate_literal?(location)

      loc = location.to_s.strip
      if iata_code?(loc)
        fetch_metar_with_extras(iata_to_icao(loc))
      elsif icao_code?(loc)
        fetch_metar_with_extras(loc.upcase)
      end
    end

    def report_location_resolution_failure(location, label)
      loc = label || location
      if gps_location_enabled? || loc == 'gps'
        error('Could not obtain GPS coordinates')
        error('  Hint: Ensure gpsd is running and the receiver has a fix')
        error('  Hint: Set gps_fallback_location in weather.ini for indoor use')
        return
      end

      error("Could not get coordinates for location: #{loc}")
      error('  Hint: Verify the postal code or location name is correct')
      error('  For IATA codes (3 letters), ensure the airport code is valid (e.g., JFK, LHR, DFW)')
      error('  For ICAO codes (4 letters), ensure the airport code is valid (e.g., KJFK, EGLL)')
      error('  Coordinates may be passed as lat,lon (e.g., 48.8566,2.3522)')
    end

    def location_label_for_error(location)
      return 'gps' if gps_location_enabled? && (location.nil? || location.empty?)

      location.to_s.empty? ? 'unknown' : location
    end

    def fetch_metar_with_extras(icao)
      metar_temp, metar_cond = fetch_metar_weather(icao)
      return [nil, nil, nil] unless WeatherNumeric.numeric_temp?(metar_temp) && metar_cond

      @weather_data = { temp: metar_temp, condition: metar_cond }
      enrich_from_airport_coordinates(icao)
      [metar_temp.round.to_s, metar_cond, 'metar']
    end

    def enrich_from_airport_coordinates(icao)
      coords = airport_coordinates(icao)
      return unless coords

      lat, lon = coords
      if extra_weather_data_needed?
        supplemental = fetch_openmeteo(lat, lon, include_extras: true)
        if supplemental
          write_timezone_file(supplemental[:timezone]) if supplemental[:timezone] && !supplemental[:timezone].empty?
          write_timezone_cache(lat, lon, supplemental[:timezone]) if supplemental[:timezone] && !supplemental[:timezone].empty?
          merge_supplemental_fields(supplemental)
        end
      else
        cached = read_timezone_cache(lat, lon)
        if cached
          write_timezone_file(cached)
        else
          fetch_timezone_openmeteo(lat, lon)
        end
      end
    end

    def merge_supplemental_fields(supplemental)
      return unless supplemental.is_a?(Hash)

      %i[precipitation wind_speed wind_direction wind_gusts pressure humidity
         feels_like dewpoint uv_index visibility_m].each do |key|
        val = supplemental[key]
        next if val.nil?
        next unless val.is_a?(Numeric)

        @weather_data[key] = val if @weather_data[key].nil?
      end
    end

    def report_coordinate_failure(location, lat, lon, provider)
      tried = @last_providers_tried&.map(&:upcase)&.join(', ')
      error("Failed to fetch weather data#{tried ? " (tried: #{tried})" : ''}")
      error("  Location: #{location}")
      error("  Coordinates: lat=#{lat}, lon=#{lon}")
      error("  Hint: Check internet connectivity and API availability")
      if @last_providers_tried&.include?('nws') && !us_coordinates?(lat, lon)
        error("  Note: NWS only supports US locations; use weather_provider = openmeteo or enable weather_provider_random")
      end
    end

    # Text output (show_* keys). Values come from WeatherValues so text and audio agree.
    def build_output_line(temp_f_display, temp_c, condition)
      mode = @config['Temperature_mode']
      data = @weather_data || {}
      deg = mode == 'F' ? 'F' : 'C'
      parts = ["#{temp_f_display}°F, #{temp_c}°C"]

      if show?('show_humidity') && (rh = humidity_value(data))
        parts << "#{rh}% RH"
      end
      if show?('show_feels_like') && (v = temperature_value(data[:feels_like], mode))
        parts << "Feels like #{v}°#{deg}"
      end
      if show?('show_dewpoint') && (v = temperature_value(data[:dewpoint], mode))
        parts << "Dewpoint #{v}°#{deg}"
      end

      parts << condition

      if show?('show_precipitation') && (v = precipitation_value(data, mode, allow_zero: true))
        parts << (mode == 'F' ? "Precip #{v} in" : "Precip #{v} mm")
      end
      if show?('show_wind') && (wind = wind_values(data, mode))
        str = "Wind #{wind[:speed]} #{mode == 'F' ? 'mph' : 'km/h'}"
        str += " #{wind[:dir]}" if wind[:dir]
        str += " (gust #{wind[:gust]})" if wind[:gust]
        parts << str
      end
      if show?('show_pressure') && (v = pressure_value(data, mode))
        parts << (mode == 'F' ? "#{v} inHG" : "#{v} hPa")
      end
      if show?('show_uv') && (v = uv_value(data))
        parts << "UV #{v}"
      end
      if show?('show_visibility') && (v = visibility_value(data, mode))
        parts << (mode == 'F' ? "Visibility #{v} mi" : "Visibility #{v} km")
      end

      parts.join(' / ')
    end

    # Radio audio extras (announce_* keys) consumed by WeatherAudio via weather_extras.json.
    def write_weather_extras_file
      mode = @config['Temperature_mode']
      data = @weather_data || {}
      segments = []

      if announce?('show_humidity') && (rh = humidity_value(data))
        segments << { 'k' => 'humidity', 'v' => rh }
      end
      if announce?('show_feels_like') && (v = temperature_value(data[:feels_like], mode))
        segments << { 'k' => 'feels_like', 'v' => v }
      end
      if announce?('show_dewpoint') && (v = temperature_value(data[:dewpoint], mode))
        segments << { 'k' => 'dewpoint', 'v' => v }
      end
      if announce?('show_wind') && (wind = wind_values(data, mode))
        segment = { 'k' => 'wind', 'speed' => wind[:speed] }
        segment['dir'] = wind[:dir] if wind[:dir]
        segment['gust'] = wind[:gust] if wind[:gust]
        segments << segment
      end
      if announce?('show_pressure') && (v = pressure_value(data, mode))
        segments << { 'k' => 'pressure', 'v' => v }
      end
      if announce?('show_precipitation') && (v = precipitation_value(data, mode, allow_zero: false))
        segments << { 'k' => 'precip', 'v' => v }
      end
      if announce?('show_uv') && (v = uv_value(data))
        segments << { 'k' => 'uv', 'v' => v }
      end
      if announce?('show_visibility') && (v = visibility_value(data, mode))
        segments << { 'k' => 'visibility', 'v' => v }
      end

      return if segments.empty?

      File.write(temp_path('weather_extras.json'), JSON.generate(segments))
    rescue => e
      warn("Error writing weather extras file: #{e.message}")
    end

    def show?(key)
      @config[key] == 'YES'
    end

    def announce?(key)
      optional_weather_announce_enabled?(key)
    end

    def write_temperature_file(temp_f, temp_c)
      temp_mode = @config['Temperature_mode']
      tmin = temp_mode == 'C' ? -60 : -100
      tmax = temp_mode == 'C' ? 60 : 150
      temp_value = temp_mode == 'C' ? temp_c : temp_f

      unless temp_value >= tmin && temp_value <= tmax
        warn("Temperature #{temp_value}°#{temp_mode} outside display range (#{tmin}..#{tmax})") if @options[:verbose]
        return false
      end

      File.write(temp_path('temperature'), temp_value.round.to_s)
      true
    rescue => e
      warn("Error writing temperature file: #{e.message}")
      false
    end
  end
end
