# frozen_string_literal: true

module SaytimeWeather
  module WeatherOptionalFields
    def optional_weather_field_enabled?(show_key)
      return false unless SaytimeWeather::OPTIONAL_WEATHER_DISPLAY_KEYS.include?(show_key)

      @config[show_key] == 'YES' || optional_weather_announce_enabled?(show_key)
    end

    def optional_weather_announce_enabled?(show_key)
      announce_key = SaytimeWeather::OPTIONAL_WEATHER_ANNOUNCE_FOR[show_key]
      announce_key && @config[announce_key] == 'YES'
    end

    def extra_weather_data_needed?
      SaytimeWeather::OPTIONAL_WEATHER_DISPLAY_KEYS.any? { |k| optional_weather_field_enabled?(k) }
    end

    def extra_weather_announce_enabled?
      SaytimeWeather::OPTIONAL_WEATHER_DISPLAY_KEYS.any? { |k| optional_weather_announce_enabled?(k) }
    end
  end
end
