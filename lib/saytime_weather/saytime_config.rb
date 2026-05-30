# frozen_string_literal: true

module SaytimeWeather
  module SaytimeConfig
    def load_config
      config_file = Paths.config_path
      if File.exist?(config_file)
        begin
          ini = Ini.parse_file(config_file)
          @config = ini['weather'] if ini && ini['weather']
        rescue => e
          warn("Failed to load config file: #{e.message}")
        end
      end

      @config['Temperature_mode'] ||= 'F'
      @config['process_condition'] ||= 'YES'
      @config['saytime_play_delay'] ||= ENV.fetch('SAYTIME_PLAY_DELAY', SAYTIME_PLAY_DELAY.to_s)
    end

    def play_delay_seconds
      val = @config['saytime_play_delay'].to_s
      return val.to_i if val =~ /^\d+$/

      SAYTIME_PLAY_DELAY
    end

    def gps_weather_enabled?
      return true if @options[:use_gps]
      return false if @options[:location_id] && !@options[:location_id].to_s.empty?

      @config['location_source'].to_s.strip.downcase == 'gps'
    end
  end
end
