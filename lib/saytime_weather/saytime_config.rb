# frozen_string_literal: true

module SaytimeWeather
  module SaytimeConfig
    def load_config
      config_file = SaytimeWeather::Paths.config_path
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
    end
  end
end
