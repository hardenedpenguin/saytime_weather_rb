# frozen_string_literal: true

require 'json'
require 'ipaddr'
require 'resolv'
require 'socket'
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

      # One budget covers resolution, every connect attempt, and the reads.
      deadline = monotonic_now + timeout_sec
      sock = connect_before(host, port, deadline)
      begin
        sock.write("?WATCH={\"enable\":true,\"json\":true}\n")
        buffer = +''
        loop do
          line = read_line_before(sock, buffer, deadline)
          break unless line

          obj = parse_gps_json(line)
          next unless obj && obj['class'] == 'TPV'
          next unless valid_tpv?(obj, min_mode, max_age)

          return extract_fix(obj)
        end
      ensure
        sock.close unless sock.closed?
      end
      nil
    rescue => e
      warn("GPS via gpsd failed: #{e.message}") if @options[:verbose]
      nil
    end

    def read_gps_from_gpspipe
      return nil unless executable_in_path?('gpspipe')

      host = gps_host
      port = gps_port
      min_mode = gps_config_int('gps_min_mode', 2)
      max_age = gps_config_int('gps_max_age_seconds', 300)
      samples = gps_config_int('gpspipe_samples', 10)

      cmd = ['gpspipe', '-w', '-n', samples.to_s]
      cmd += ['-h', host] unless host == '127.0.0.1'
      cmd += ['-p', port.to_s] unless port == 2947

      timeout_sec = gps_config_int('gps_timeout_seconds', 5)
      output = read_command_output(cmd, timeout_sec)
      return nil unless output

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

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Open a TCP connection to gpsd, never past +deadline+ (monotonic seconds).
    # Resolution and each address attempt get only the remaining budget, and no new
    # attempt starts once it is spent. Raises the last error when nothing connects.
    def connect_before(host, port, deadline)
      last_error = nil
      resolve_before(host, deadline).each do |ip|
        remaining = deadline - monotonic_now
        break if remaining <= 0

        begin
          return Socket.tcp(ip, port, connect_timeout: remaining)
        rescue SystemCallError, SocketError => e
          last_error = e
        end
      end
      raise last_error || Errno::ETIMEDOUT.new("connect to #{host}:#{port}")
    end

    # IP literals skip resolution. Names use /etc/hosts, then DNS limited to the
    # remaining budget (Resolv works on Ruby 2.7, unlike Socket.tcp resolv_timeout).
    def resolve_before(host, deadline)
      return [host] if ip_literal?(host)

      addrs = Resolv::Hosts.new.getaddresses(host)
      return addrs unless addrs.empty?

      remaining = deadline - monotonic_now
      raise Errno::ETIMEDOUT, "resolve #{host}" if remaining <= 0

      Resolv::DNS.open do |dns|
        dns.timeouts = remaining
        addrs = dns.getresources(host, Resolv::DNS::Resource::IN::A).map { |r| r.address.to_s }
        addrs += dns.getresources(host, Resolv::DNS::Resource::IN::AAAA).map { |r| r.address.to_s } if (deadline - monotonic_now).positive?
      end
      raise SocketError, "could not resolve #{host}" if addrs.empty?

      addrs
    end

    def ip_literal?(host)
      IPAddr.new(host)
      true
    rescue IPAddr::InvalidAddressError, ArgumentError
      false
    end

    # Read one newline-terminated line, waiting at most until +deadline+ (monotonic seconds).
    # Returns nil on timeout or EOF. Uses IO.select instead of Timeout.timeout, which can
    # interrupt code at unsafe points.
    def read_line_before(sock, buffer, deadline)
      loop do
        if (idx = buffer.index("\n"))
          return buffer.slice!(0..idx)
        end

        remaining = deadline - monotonic_now
        return nil if remaining <= 0
        return nil unless IO.select([sock], nil, nil, remaining)

        chunk = sock.read_nonblock(4096, exception: false)
        next if chunk == :wait_readable
        return nil if chunk.nil?

        buffer << chunk
        return nil if buffer.bytesize > 1_048_576
      end
    end

    # Run +cmd+ and collect stdout for at most +timeout_sec+ seconds; the child is
    # terminated if it is still running at the deadline (e.g. gpspipe waiting for samples).
    def read_command_output(cmd, timeout_sec)
      deadline = monotonic_now + timeout_sec
      output = +''
      IO.popen(cmd, err: File::NULL) do |io|
        loop do
          remaining = deadline - monotonic_now
          break if remaining <= 0
          break unless IO.select([io], nil, nil, remaining)

          chunk = io.read_nonblock(4096, exception: false)
          next if chunk == :wait_readable
          break if chunk.nil?

          output << chunk
        end
        unless io.closed?
          begin
            Process.kill('TERM', io.pid)
          rescue Errno::ESRCH
            nil
          end
        end
      end
      output.empty? ? nil : output
    end

    def executable_in_path?(name)
      ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
        path = File.join(dir, name)
        File.file?(path) && File.executable?(path)
      end
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
