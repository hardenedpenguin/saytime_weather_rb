# frozen_string_literal: true

require 'json'
require 'optparse'
require 'fileutils'

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
    include WeatherSound
    include WeatherProviders
    include WeatherGps

    attr_reader :options, :config

    def initialize(options: nil)
      @options = {
        verbose: false,
        config_file: nil,
        default_country: nil,
        temperature_mode: nil,
        no_condition: false,
        use_gps: false
      }
      @config = {}
      @provider_explicitly_set = false
      @airport_iata_map = nil
      @airport_icao_coords = nil
      @explicit_location = false

      if options
        merge_runtime_options(options)
      else
        parse_options
      end

      @http = HttpClient.new(warn_proc: ->(m) { warn(m) }, verbose: @options[:verbose])
      load_config
    end

    def merge_runtime_options(opts)
      @options[:verbose] = true if opts[:verbose]
      @options[:config_file] = opts[:config_file] if opts[:config_file]
      @options[:default_country] = opts[:default_country] if opts[:default_country]
      @options[:temperature_mode] = opts[:temperature_mode].upcase if opts[:temperature_mode]
      @options[:no_condition] = true if opts[:no_condition]
      @options[:use_gps] = true if opts[:use_gps]
    end

    def parse_options
      OptionParser.new do |opts|
        opts.banner = "weather.rb version #{VERSION}\n\nUsage: #{File.basename($PROGRAM_NAME)} [OPTIONS] [location_id] [v]\n\n"

        opts.on('-c', '--config FILE', 'Use alternate configuration file') { |f| @options[:config_file] = f }
        opts.on('-d', '--default-country CC', 'Override default country') { |cc| @options[:default_country] = cc }
        opts.on('-t', '--temperature-mode M', 'Override temperature mode (F or C)') { |m| @options[:temperature_mode] = m.upcase }
        opts.on('--no-condition', 'Skip weather condition announcements') { @options[:no_condition] = true }
        opts.on('--gps', 'Use GPS coordinates from gpsd (location_id optional)') { @options[:use_gps] = true }
        opts.on('-v', '--verbose', 'Enable verbose output') { @options[:verbose] = true }
        opts.on('-h', '--help', 'Show this help message') { show_usage; exit 0 }
        opts.on('--version', 'Show version information') { puts "weather.rb version #{VERSION}"; exit 0 }
      end.parse!
    end

    def show_usage
      puts "weather.rb version #{VERSION}\n\n"
      puts "Usage: weather.rb [OPTIONS] [location_id] [v]\n\n"
      puts "Arguments:"
      puts "  location_id    Postal code, IATA, ICAO, lat,lon coordinates, or omit with --gps"
      puts "  v              Display text only (no sound output)\n\n"
      puts "Options:"
      puts "  -c, --config FILE        Alternate configuration file"
      puts "  -d, --default-country CC Override default country"
      puts "  -t, --temperature-mode M Temperature mode (F or C)"
      puts "  --no-condition           Skip condition sound files"
      puts "  --gps                    Use GPS via gpsd (see location_source = gps in weather.ini)"
      puts "  -v, --verbose            Verbose output"
      puts "  -h, --help               This help"
      puts "  --version                Version information\n\n"
      puts "Configuration: #{Paths.config_path}\n"
      puts "GPS: set location_source = gps in weather.ini or pass --gps. Requires gpsd.\n"
      puts "Note: show_precipitation, show_wind, show_pressure, and show_humidity apply to"
      puts "postal-code lookups only; airport METAR provides temperature and condition.\n"
    end

  # Returns true on success, false on failure (does not exit).
  def run(location: nil, display_only: nil)
      @http.verbose = @options[:verbose]
      location = (location || ARGV[0]).to_s unless gps_location_enabled?
      display_only = display_only || ARGV[1]
      @explicit_location = !location.to_s.strip.empty?

      if !gps_location_enabled? && location.empty?
        show_usage
        return :usage
      end

      unless valid_location_format?(location)
        error("Invalid location format.")
        error("  Provided: #{location}")
        error("  Use postal code, airport code, lat,lon coordinates, or --gps")
        return false
      end

      location = location.strip unless location.empty?
      cleanup_old_files

      temperature, condition, provider = fetch_weather_for_location(location)

      unless temperature && condition
        label = location_label_for_error(location)
        error("No weather report available")
        error("  Location: #{label}")
        error("  Hint: Check that the location is valid and weather services are accessible")
        return false
      end

      temp_f = temperature.to_f
      unless temp_f >= -150.0 && temp_f <= 200.0
        error("Invalid temperature value: #{temp_f}°F")
        error("  Location: #{location_label_for_error(location)}")
        return false
      end

      temp_c = ((5.0 / 9.0) * (temp_f - 32)).round
      puts build_output_line(temp_f.round, temp_c, condition)

      return true if display_only == 'v'

      write_temperature_file(temp_f, temp_c)
      process_weather_condition(condition) if @config['process_condition'] == 'YES' && condition
      true
    ensure
      @http.close if @http
    end

    private

    def fetch_weather_for_location(location)
      @weather_data = {}
      @resolved_metar = nil

      if (metar = try_metar_resolution(location))
        return metar
      end

      lat, lon, label = resolve_location_coordinates(location)
      if lat && lon
        weather_data, provider = fetch_coordinate_weather(lat, lon, label)
        if weather_data && weather_data[:temp] && weather_data[:condition]
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

    def try_metar_resolution(location)
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
      return [nil, nil, nil] unless metar_temp && metar_cond

      @weather_data = { temp: metar_temp, condition: metar_cond }
      enrich_from_airport_coordinates(icao)
      [metar_temp.round.to_s, metar_cond, 'metar']
    end

    def enrich_from_airport_coordinates(icao)
      coords = airport_coordinates(icao)
      return unless coords

      lat, lon = coords
      if extra_weather_fields_enabled?
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

      %i[precipitation wind_speed wind_direction wind_gusts pressure humidity].each do |key|
        val = supplemental[key]
        next if val.nil?
        next unless val.is_a?(Numeric)

        @weather_data[key] = val if @weather_data[key].nil?
      end
    end

    def extra_weather_fields_enabled?
      %w[show_precipitation show_wind show_pressure show_humidity].any? { |k| @config[k] == 'YES' }
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

    def build_output_line(temp_f_display, temp_c, condition)
      temp_mode = @config['Temperature_mode']
      weather_data = @weather_data || {}
      output_parts = ["#{temp_f_display}°F, #{temp_c}°C"]

      if @config['show_humidity'] == 'YES' && weather_data[:humidity]
        humidity_val = weather_data[:humidity]
        output_parts << "#{humidity_val.round}% RH" if humidity_val.is_a?(Numeric)
      end

      output_parts << condition
      append_precipitation(output_parts, weather_data, temp_mode)
      append_wind(output_parts, weather_data, temp_mode)
      append_pressure(output_parts, weather_data, temp_mode)
      output_parts.join(' / ')
    end

    def append_precipitation(output_parts, weather_data, temp_mode)
      return unless @config['show_precipitation'] == 'YES' && weather_data[:precipitation]

      precip_mm = weather_data[:precipitation]
      return unless precip_mm.is_a?(Numeric)

      show_precip = precip_mm > 0 || @config['show_zero_precip'] == 'YES'
      if show_precip && precip_mm > 0
        trace_threshold = @config['precip_trace_mm'].to_f
        show_precip = false if precip_mm < trace_threshold && @config['show_zero_precip'] != 'YES'
      end

      return unless show_precip

      if temp_mode == 'F'
        precip_in = mm_to_inches(precip_mm)
        output_parts << "Precip #{precip_in} in" if precip_in
      else
        output_parts << "Precip #{precip_mm.round(2)} mm"
      end
    end

    def append_wind(output_parts, weather_data, temp_mode)
      return unless @config['show_wind'] == 'YES' && weather_data[:wind_speed]

      wind_ms = weather_data[:wind_speed]
      return unless wind_ms.is_a?(Numeric) && wind_ms > 0

      wind_str = 'Wind'
      if temp_mode == 'F'
        wind_mph = ms_to_mph(wind_ms)
        wind_str += " #{wind_mph} mph" if wind_mph
      else
        wind_kmh = ms_to_kmh(wind_ms)
        wind_str += " #{wind_kmh} km/h" if wind_kmh
      end

      if weather_data[:wind_direction].is_a?(Numeric)
        dir = wind_direction_to_cardinal(weather_data[:wind_direction])
        wind_str += " #{dir}" if dir
      end

      if weather_data[:wind_gusts].is_a?(Numeric) && weather_data[:wind_gusts] > wind_ms
        gust = temp_mode == 'F' ? ms_to_mph(weather_data[:wind_gusts]) : ms_to_kmh(weather_data[:wind_gusts])
        wind_str += " (gust #{gust})" if gust
      end

      output_parts << wind_str
    end

    def append_pressure(output_parts, weather_data, temp_mode)
      return unless @config['show_pressure'] == 'YES' && weather_data[:pressure]

      pressure_hpa = weather_data[:pressure]
      return unless pressure_hpa.is_a?(Numeric)

      if temp_mode == 'F'
        pressure_inhg = hpa_to_inhg(pressure_hpa)
        output_parts << "#{pressure_inhg} inHG" if pressure_inhg
      else
        output_parts << "#{pressure_hpa.round} hPa"
      end
    end

    def write_temperature_file(temp_f, temp_c)
      temp_mode = @config['Temperature_mode']
      tmin = temp_mode == 'C' ? -60 : -100
      tmax = temp_mode == 'C' ? 60 : 150
      temp_value = temp_mode == 'C' ? temp_c : temp_f

      return unless temp_value >= tmin && temp_value <= tmax

      File.write(temp_path('temperature'), temp_value.round.to_s)
    rescue => e
      warn("Error writing temperature file: #{e.message}")
    end
  end
end
