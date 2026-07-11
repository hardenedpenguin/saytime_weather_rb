# frozen_string_literal: true

module SaytimeWeather
  module WeatherNumeric
    module_function

    def numeric_temp?(val)
      !val.nil? && val.is_a?(Numeric)
    end

    def valid_condition?(condition)
      text = condition.to_s.strip
      !text.empty? && text != 'Unknown'
    end

    def valid_weather_data?(data)
      data && numeric_temp?(data[:temp]) && valid_condition?(data[:condition])
    end
  end
end
