# frozen_string_literal: true

module SaytimeWeather
  module WeatherNumeric
    module_function

    def numeric_temp?(val)
      !val.nil? && val.is_a?(Numeric)
    end

    def valid_weather_data?(data)
      data && numeric_temp?(data[:temp]) && data[:condition] && !data[:condition].to_s.empty?
    end
  end
end
