# frozen_string_literal: true

module SaytimeWeather
  module WeatherUnits
    def mm_to_inches(mm)
      return nil unless mm && mm.is_a?(Numeric)
      (mm / 25.4).round(2)
    end

    def ms_to_mph(ms)
      return nil unless ms && ms.is_a?(Numeric)
      (ms * 2.23694).round
    end

    def ms_to_kmh(ms)
      return nil unless ms && ms.is_a?(Numeric)
      (ms * 3.6).round
    end

    def hpa_to_inhg(hpa)
      return nil unless hpa && hpa.is_a?(Numeric)
      (hpa * 0.02953).round(2)
    end

    def wind_direction_to_cardinal(degrees)
      return nil unless degrees && degrees.is_a?(Numeric)
      directions = %w[N NNE NE ENE E ESE SE SSE S SSW SW WSW W WNW NW NNW]
      index = ((degrees + 11.25) / 22.5).round % 16
      directions[index]
    end
  end
end
