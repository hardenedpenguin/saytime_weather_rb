# frozen_string_literal: true

require 'json'
require 'socket'
require 'timeout'
require 'time'

module SaytimeWeather
  module WeatherGps
    def gps_location_enabled?
      return false if @explicit_location
      return true if @options[:use_gps]

      @config['location_source'].to_s.strip.downcase == 'gps'
    end

    def read_gps_fix
      fix = read_gps_from_gpsd
      fix ||= read_gps_from_gpspipe if gpspipe_fallback?

      if fix
        fix = normalize_gps_fix(fix)
        write_gps_fix_cache(fix)
        if @options[:verbose]
          warn("GPS fix: lat=#{fix[:lat]}, lon=#{fix[:lon]} (mode #{fix[:mode]})")
        end
        return fix
      end

      cached = read_gps_fix_cache
      if cached
        age = (Time.now - cached[:time]).to_i
        max_cache = gps_config_int('gps_fix_cache_max_age_seconds', 86_400)
        if max_cache <= 0 || age <= max_cache
          warn("Using cached GPS fix (#{age}s old)") if @options[:verbose]
          return cached
        end
      end

      nil
    end

    def format_gps_label(fix)
      "gps:#{fix[:lat]},#{fix[:lon]}"
    end

    private

    def gps_config_int(key, default)
      val = @config[key].to_s
      return default unless val =~ /^\d+$/

      val.to_i
    end

    def gps_host
      host = @config['gpsd_host'].to_s.strip
      host.empty? ? '127.0.0.1' : host
    end

    def gps_port
      gps_config_int('gpsd_port', 2947)
    end

    def gpspipe_fallback?
      mode = @config['gps_use_gpspipe'].to_s.strip.upcase
      return true if mode.empty? || mode == 'AUTO'
      return true if mode == 'YES'

      false
    end

    def read_gps_from_gpsd
      host = gps_host
      port = gps_port
      timeout_sec = gps_config_int('gps_timeout_seconds', 5)
      min_mode = gps_config_int('gps_min_mode', 2)
      max_age = gps_config_int('gps_max_age_seconds', 300)

      Timeout.timeout(timeout_sec) do
        Socket.tcp(host, port) do |sock|
          sock.write("?WATCH={\"enable\":true,\"json\":true}\n")
          deadline = Time.now + timeout_sec
          while Time.now < deadline
            line = sock.gets
            break unless line

            obj = parse_gps_json(line)
            next unless obj && obj['class'] == 'TPV'
            next unless valid_tpv?(obj, min_mode, max_age)

            return extract_fix(obj)
          end
        end
      end
      nil
    rescue => e
      warn("GPS via gpsd failed: #{e.message}") if @options[:verbose]
      nil
    end

    def read_gps_from_gpspipe
      return nil unless system('which', 'gpspipe', out: File::NULL, err: File::NULL)

      host = gps_host
      port = gps_port
      min_mode = gps_config_int('gps_min_mode', 2)
      max_age = gps_config_int('gps_max_age_seconds', 300)
      samples = gps_config_int('gpspipe_samples', 10)

      cmd = ['gpspipe', '-w', '-n', samples.to_s]
      cmd += ['-h', host] unless host == '127.0.0.1'
      cmd += ['-p', port.to_s] unless port == 2947

      output = nil
      IO.popen(cmd, err: [:child, :out]) { |io| output = io.read }
      return nil unless $?.success? && output

      output.each_line do |line|
        obj = parse_gps_json(line)
        next unless obj && obj['class'] == 'TPV'
        next unless valid_tpv?(obj, min_mode, max_age)

        return extract_fix(obj)
      end
      nil
    rescue => e
      warn("GPS via gpspipe failed: #{e.message}") if @options[:verbose]
      nil
    end

    def parse_gps_json(line)
      stripped = line.to_s.strip
      return nil unless stripped.start_with?('{')

      JSON.parse(stripped)
    rescue JSON::ParserError
      nil
    end

    def valid_tpv?(obj, min_mode, max_age)
      mode = obj['mode'].to_i
      return false if mode < min_mode

      lat = obj['lat']
      lon = obj['lon']
      return false unless lat.is_a?(Numeric) && lon.is_a?(Numeric)
      return false if lat.abs < 0.0001 && lon.abs < 0.0001

      fix_time = parse_gps_time(obj['time'])
      return false if fix_time && max_age.positive? && (Time.now - fix_time) > max_age

      true
    end

    def extract_fix(obj)
      {
        lat: round_gps_coord(obj['lat']),
        lon: round_gps_coord(obj['lon']),
        mode: obj['mode'].to_i,
        time: parse_gps_time(obj['time']) || Time.now,
        source: 'gps'
      }
    end

    def normalize_gps_fix(fix)
      {
        lat: round_gps_coord(fix[:lat]),
        lon: round_gps_coord(fix[:lon]),
        mode: fix[:mode].to_i,
        time: fix[:time].is_a?(Time) ? fix[:time] : Time.now,
        source: fix[:source].to_s
      }
    end

    def round_gps_coord(val)
      prec = gps_config_int('gps_coordinate_precision', 4)
      val.to_f.round(prec)
    end

    def parse_gps_time(value)
      return nil if value.nil? || value.to_s.empty?

      Time.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def write_gps_fix_cache(fix)
      Cache.write_json(Paths.gps_fix_cache_path, {
                         'lat' => fix[:lat],
                         'lon' => fix[:lon],
                         'mode' => fix[:mode],
                         'time' => fix[:time].utc.iso8601,
                         'source' => fix[:source]
                       })
    end

    def read_gps_fix_cache
      data = Cache.read_json(Paths.gps_fix_cache_path, 0)
      return nil unless data && data['lat'] && data['lon']

      {
        lat: data['lat'].to_f,
        lon: data['lon'].to_f,
        mode: data['mode'].to_i,
        time: parse_gps_time(data['time']) || Time.at(0),
        source: data['source'].to_s
      }
    rescue
      nil
    end
  end
end
