# frozen_string_literal: true

require_relative 'weather_units'

module SaytimeWeather
  # Optional weather fields converted to the configured display units.
  # Shared by text output (show_*) and radio audio (announce_*) so both apply the same
  # thresholds and rounding. Each method returns nil when the value should be omitted.
  module WeatherValues
    include WeatherUnits

    def humidity_value(data)
      rh = data[:humidity]
      rh.is_a?(Numeric) ? rh.round : nil
    end

    # Temperature-like field stored in °F (feels-like, dewpoint).
    def temperature_value(fahrenheit, mode)
      return nil unless fahrenheit.is_a?(Numeric)

      mode == 'F' ? fahrenheit.round : fahrenheit_to_celsius(fahrenheit)
    end

    # Precipitation in inches (F) or mm (C). Amounts under precip_trace_mm are dropped
    # unless show_zero_precip = YES. allow_zero keeps a zero reading when
    # show_zero_precip = YES (text output); audio never speaks zero.
    def precipitation_value(data, mode, allow_zero:)
      mm = data[:precipitation]
      return nil unless mm.is_a?(Numeric)

      show_zero = @config['show_zero_precip'] == 'YES'
      if mm.positive?
        return nil if !show_zero && mm < @config['precip_trace_mm'].to_f
      else
        return nil unless allow_zero && show_zero
      end

      mode == 'F' ? mm_to_inches(mm) : mm.round(2)
    end

    # { speed:, dir:, gust: } in mph (F) or km/h (C); nil when calm or unknown.
    def wind_values(data, mode)
      ms = data[:wind_speed]
      return nil unless ms.is_a?(Numeric) && ms.positive?

      convert = mode == 'F' ? method(:ms_to_mph) : method(:ms_to_kmh)
      wind = { speed: convert.call(ms) }
      wind[:dir] = wind_direction_to_cardinal(data[:wind_direction]) if data[:wind_direction].is_a?(Numeric)
      gusts = data[:wind_gusts]
      wind[:gust] = convert.call(gusts) if gusts.is_a?(Numeric) && gusts > ms
      wind.compact
    end

    # Pressure in inHg (F) or hPa (C).
    def pressure_value(data, mode)
      hpa = data[:pressure]
      return nil unless hpa.is_a?(Numeric)

      mode == 'F' ? hpa_to_inhg(hpa) : hpa.round
    end

    def uv_value(data)
      uv = data[:uv_index]
      uv.is_a?(Numeric) ? uv.round : nil
    end

    # Visibility in miles (F) or km (C).
    def visibility_value(data, mode)
      m = data[:visibility_m]
      return nil unless m.is_a?(Numeric) && !m.negative?

      mode == 'F' ? meters_to_miles(m) : meters_to_km(m)
    end
  end
end
