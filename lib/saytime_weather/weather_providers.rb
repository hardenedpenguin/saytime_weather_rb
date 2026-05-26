# frozen_string_literal: true

module SaytimeWeather
  module WeatherProviders
    PROVIDERS = %w[openmeteo nws metno wttr 7timer].freeze
    WORLDWIDE_PROVIDERS = %w[openmeteo metno wttr 7timer].freeze

    def provider_random_enabled?
      @config['weather_provider_random'] == 'YES'
    end

    def us_coordinates?(lat, lon)
      lat >= 18.0 && lat <= 72.0 && lon >= -180.0 && lon <= -50.0
    end

    def configured_provider
      provider = @config['weather_provider'].to_s.downcase
      PROVIDERS.include?(provider) ? provider : 'openmeteo'
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

    # Random mode: try shuffled providers except the configured default, then the rest.
    def provider_try_order_random(lat, lon)
      default = configured_provider
      eligible = eligible_providers(lat, lon)
      random_first = (eligible - [default]).shuffle
      remainder = eligible - random_first - [default]
      (random_first + remainder + [default]).uniq
    end

    # Fixed mode: configured provider; legacy US auto-NWS when openmeteo is implicit default.
    def provider_try_order_fixed(lat, lon)
      default = configured_provider
      if !@provider_explicitly_set && us_coordinates?(lat, lon) && default == 'openmeteo'
        %w[nws openmeteo]
      else
        [default]
      end
    end

    def provider_try_order(lat, lon)
      provider_random_enabled? ? provider_try_order_random(lat, lon) : provider_try_order_fixed(lat, lon)
    end

    def fetch_coordinate_weather(lat, lon, _location)
      try_order = provider_try_order(lat, lon)
      last_provider = try_order.first || configured_provider

      try_order.each do |provider|
        data = fetch_from_provider(provider, lat, lon)
        next unless valid_weather_data?(data)

        if @options[:verbose]
          mode = provider_random_enabled? ? 'random rotation' : 'configured'
          warn("Weather from #{provider.upcase} (#{mode})")
        end
        return [data, provider]
      end

      [nil, last_provider]
    end
  end
end
