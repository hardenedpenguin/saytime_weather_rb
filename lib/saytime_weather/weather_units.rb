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
      index = ((degrees + 11.25) / 22.5).to_i % 16
      directions[index]
    end

    def mph_to_ms(mph)
      return nil unless mph && mph.is_a?(Numeric)

      mph / 2.23694
    end

    def celsius_to_fahrenheit(c)
      return nil unless c.is_a?(Numeric)

      (c * 9.0 / 5.0) + 32.0
    end

    def fahrenheit_to_celsius(f)
      return nil unless f.is_a?(Numeric)

      ((f - 32) * 5.0 / 9.0).round
    end

    def meters_to_miles(m)
      return nil unless m.is_a?(Numeric)

      (m / 1609.344).round(1)
    end

    def meters_to_km(m)
      return nil unless m.is_a?(Numeric)

      (m / 1000.0).round(1)
    end
  end
end
