# frozen_string_literal: true

module SaytimeWeather
  module WeatherProviders
    PROVIDERS = %w[openmeteo nws metno wttr 7timer].freeze
    WORLDWIDE_PROVIDERS = %w[openmeteo metno wttr 7timer].freeze

    def provider_random_enabled?
      @config['weather_provider_random'] == 'YES'
    end

    def random_max_attempts
      n = Network.random_max_attempts
      n = @config['weather_provider_random_max_attempts'].to_i if @config['weather_provider_random_max_attempts'].to_s =~ /^\d+$/
      n
    end

    def us_coordinates?(lat, lon)
      lat >= 18.0 && lat <= 72.0 && lon >= -180.0 && lon <= -50.0
    end

    def configured_provider
      provider = @config['weather_provider'].to_s.downcase
      PROVIDERS.include?(provider) ? provider : 'openmeteo'
    end

    def effective_default_provider(lat, lon)
      default = configured_provider
      return 'openmeteo' if default == 'nws' && !us_coordinates?(lat, lon)

      default
    end

    def eligible_providers(lat, lon)
      list = WORLDWIDE_PROVIDERS.dup
      list.unshift('nws') if us_coordinates?(lat, lon)
      list
    end

    def fetch_from_provider(provider, lat, lon)
      case provider
      when 'nws'
        fetch_weather_nws(lat, lon)
      when 'metno'
        fetch_weather_metno(lat, lon)
      when 'wttr'
        fetch_weather_wttr(lat, lon)
      when '7timer'
        fetch_weather_7timer(lat, lon)
      else
        fetch_weather_openmeteo(lat, lon)
      end
    end

    def valid_weather_data?(data)
      data && data[:temp] && data[:condition]
    end

    def ensure_location_timezone(lat, lon, data)
      tz = data[:timezone].to_s.strip
      if tz.empty?
        cached = read_timezone_cache(lat, lon)
        if cached
          write_timezone_file(cached)
        else
          fetched = fetch_timezone_openmeteo(lat, lon)
          write_timezone_cache(lat, lon, fetched) if fetched && !fetched.empty?
        end
      else
        write_timezone_file(tz)
        write_timezone_cache(lat, lon, tz)
      end
    end

    def provider_try_order_random(lat, lon)
      default = effective_default_provider(lat, lon)
      eligible = eligible_providers(lat, lon)
      random_pool = (eligible - [default]).shuffle

      max = random_max_attempts
      if max > 0
        random_pool = random_pool.first([max - 1, 0].max)
      end

      sanitize_try_order(random_pool + [default], lat, lon)
    end

    def provider_try_order_fixed(lat, lon)
      default = effective_default_provider(lat, lon)
      order =
        if !@provider_explicitly_set && us_coordinates?(lat, lon) && configured_provider == 'openmeteo'
          %w[nws openmeteo]
        else
          [default]
        end
      sanitize_try_order(order, lat, lon)
    end

    def sanitize_try_order(order, lat, lon)
      order = order.reject { |p| p == 'nws' } unless us_coordinates?(lat, lon)
      order << 'openmeteo' unless order.include?('openmeteo')
      order.uniq
    end

    def provider_try_order(lat, lon)
      provider_random_enabled? ? provider_try_order_random(lat, lon) : provider_try_order_fixed(lat, lon)
    end

    def fetch_coordinate_weather(lat, lon, _location)
      try_order = provider_try_order(lat, lon)
      @last_providers_tried = []
      default = effective_default_provider(lat, lon)

      try_order.each do |provider|
        @last_providers_tried << provider
        data = fetch_from_provider_with_timeout(provider, lat, lon, default)
        next unless valid_weather_data?(data)

        ensure_location_timezone(lat, lon, data)

        if @options[:verbose]
          mode = provider_random_enabled? ? 'random rotation' : 'configured'
          warn("Weather from #{provider.upcase} (#{mode})")
          if data[:observation_time] && !data[:observation_time].to_s.empty?
            tz = data[:timezone].to_s.strip
            place = tz.empty? ? '' : " (#{tz})"
            warn("Observation time: #{data[:observation_time]}#{place} at #{format('%.4f, %.4f', lat, lon)}")
          end
        end
        return [data, provider]
      end

      [nil, try_order.last || configured_provider]
    end

    def fetch_from_provider_with_timeout(provider, lat, lon, default)
      prev_short = Network.timeout_short
      prev_long = Network.timeout_long
      t = provider_random_enabled? && provider != default ? Network.probe_timeout : Network.timeout_long
      Network.timeout_short = [prev_short, t].min
      Network.timeout_long = t
      fetch_from_provider(provider, lat, lon)
    ensure
      Network.timeout_short = prev_short
      Network.timeout_long = prev_long
    end
  end
end
