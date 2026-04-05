# frozen_string_literal: true

require 'fileutils'

module SaytimeWeather
  module WeatherConfig
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
  end
end
