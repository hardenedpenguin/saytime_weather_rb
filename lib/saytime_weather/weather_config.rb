# frozen_string_literal: true

require 'fileutils'
require_relative 'config_error'

module SaytimeWeather
  module WeatherConfig
    def load_config
      config_path = @options[:config_file] || SaytimeWeather::Paths.config_path

      if @options[:config_file] && !File.exist?(@options[:config_file])
        raise ConfigError, "Custom config file not found: #{@options[:config_file]}"
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

      @config['process_condition'] ||= 'YES'
      @config['Temperature_mode'] ||= 'F'
      @config['default_country'] ||= 'us'
      @config['weather_provider'] ||= 'openmeteo'
      @config['weather_provider_random'] ||= 'YES'
      @config['show_precipitation'] ||= 'NO'
      @config['show_wind'] ||= 'NO'
      @config['show_pressure'] ||= 'NO'
      @config['show_humidity'] ||= 'NO'
      @config['show_zero_precip'] ||= 'NO'
      @config['precip_trace_mm'] ||= '0.10'
      @config['location_source'] ||= 'postal'

      if @options[:default_country]
        ini_country = @config['default_country']
        @config['default_country'] = @options[:default_country].downcase
        if @options[:verbose] && ini_country && ini_country.downcase != @config['default_country']
          warn("Using -d country override: #{@config['default_country']} (weather.ini has #{ini_country.downcase})")
        end
      end
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
      n.probe_timeout = @config['http_probe_timeout'].to_i if @config['http_probe_timeout'].to_s =~ /^\d+$/
      if @config['airports_cache_max_age_seconds'].to_s =~ /^\d+$/
        n.airports_cache_max_age = @config['airports_cache_max_age_seconds'].to_i
      end
      if @config['geocode_cache_max_age_seconds'].to_s =~ /^\d+$/
        n.geocode_cache_max_age = @config['geocode_cache_max_age_seconds'].to_i
      end
      if @config['timezone_cache_max_age_seconds'].to_s =~ /^\d+$/
        n.timezone_cache_max_age = @config['timezone_cache_max_age_seconds'].to_i
      end
      if @config['weather_provider_random_max_attempts'].to_s =~ /^\d+$/
        n.random_max_attempts = @config['weather_provider_random_max_attempts'].to_i
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
        ; weather_provider = openmeteo
        ; Omit weather_provider to rotate across providers (Open-Meteo tried last).
        ; US postal codes without weather_provider set use NWS then Open-Meteo when
        ; weather_provider_random = NO.
        weather_provider_random = YES
        show_precipitation = NO
        show_wind = NO
        show_pressure = NO
        show_humidity = NO
        show_zero_precip = NO
        precip_trace_mm = 0.10
        ; show_* options apply to postal-code lookups; airport METAR adds extras when enabled.
        ; Optional network tuning (defaults shown; uncomment to override)
        ; http_timeout_short = 10
        ; http_timeout_long = 15
        ; http_probe_timeout = 5
        ; nominatim_delay = 1
        ; http_get_retries = 3
        ; http_get_retry_sleep = 1
        ; geocode_cache_max_age_seconds = 2592000
        ; timezone_cache_max_age_seconds = 604800
        ; weather_provider_random_max_attempts = 3
        ; weatherapi_key = YOUR_KEY_HERE
        ; saytime_play_delay = 5
        ; airports_cache_max_age_seconds = 604800
        ; airports_data_url = https://ourairports.com/data/airports.csv
      CONFIG
      File.write(config_path, default_config)
      File.chmod(0o644, config_path)
    end

    def validate_config
      temp_mode = @config['Temperature_mode'].to_s
      unless temp_mode =~ /^[CF]$/
        raise ConfigError, "Invalid Temperature_mode: #{@config['Temperature_mode']}"
      end

      provider = @config['weather_provider'].to_s.downcase
      unless %w[openmeteo nws metno wttr 7timer weatherapi].include?(provider)
        warn("Invalid weather_provider: #{@config['weather_provider']}, using default (openmeteo)")
        @config['weather_provider'] = 'openmeteo'
        provider = 'openmeteo'
      end

      if provider == 'weatherapi' && !weatherapi_key_configured?
        raise ConfigError, 'weather_provider is weatherapi but weatherapi_key (or WEATHERAPI_KEY) is not set'
      end

      source = @config['location_source'].to_s.strip.downcase
      unless %w[postal gps].include?(source)
        warn("Invalid location_source: #{@config['location_source']}, using default (postal)")
        @config['location_source'] = 'postal'
      end
    end

    def weatherapi_key_configured?
      key = @config['weatherapi_key'].to_s.strip
      key = ENV['WEATHERAPI_KEY'].to_s.strip if key.empty?
      !key.empty?
    end
  end
end
