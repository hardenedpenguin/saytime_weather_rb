# frozen_string_literal: true

require_relative 'weather_optional_fields'

module SaytimeWeather
  module WeatherMetNo
    include WeatherOptionalFields

    def fetch_weather_metno(lat, lon)
      return nil if lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0

      url = SaytimeWeather::Endpoints.met_no_compact_url(lat, lon)
      ua = SaytimeWeather::Endpoints::MET_NO_API_UA
      response = @http.get(url, SaytimeWeather::Network.timeout_long, ua)
      return nil unless response

      data = safe_decode_json(response)
      return nil unless data && data['properties'] && data['properties']['timeseries'].is_a?(Array)

      ts = data['properties']['timeseries'][0]
      return nil unless ts && ts['data'] && ts['data']['instant'] && ts['data']['instant']['details']

      details = ts['data']['instant']['details']
      temp_c = details['air_temperature']
      return nil unless temp_c.is_a?(Numeric)

      temp_f = (temp_c * 9.0 / 5.0) + 32.0

      symbol_code =
        if ts['data']['next_1_hours'] && ts['data']['next_1_hours']['summary']
          ts['data']['next_1_hours']['summary']['symbol_code']
        elsif ts['data']['next_6_hours'] && ts['data']['next_6_hours']['summary']
          ts['data']['next_6_hours']['summary']['symbol_code']
        elsif ts['data']['next_12_hours'] && ts['data']['next_12_hours']['summary']
          ts['data']['next_12_hours']['summary']['symbol_code']
        end

      condition = metno_symbol_to_text(symbol_code)
      return nil unless condition

      precipitation = nil
      if optional_weather_field_enabled?('show_precipitation') && ts['data']['next_1_hours'] && ts['data']['next_1_hours']['details']
        pmm = ts['data']['next_1_hours']['details']['precipitation_amount']
        precipitation = pmm if pmm.is_a?(Numeric)
      end

      wind_speed = nil
      wind_direction = nil
      if optional_weather_field_enabled?('show_wind')
        ws = details['wind_speed']
        wind_speed = ws if ws.is_a?(Numeric)
        wd = details['wind_from_direction']
        wind_direction = wd if wd.is_a?(Numeric)
      end

      pressure = nil
      if optional_weather_field_enabled?('show_pressure')
        p = details['air_pressure_at_sea_level']
        pressure = p if p.is_a?(Numeric)
      end

      humidity = nil
      if optional_weather_field_enabled?('show_humidity')
        rh = details['relative_humidity']
        humidity = rh if rh.is_a?(Numeric)
      end

      dewpoint = nil
      if optional_weather_field_enabled?('show_dewpoint')
        dp_c = details['dew_point_temperature']
        dewpoint = celsius_to_fahrenheit(dp_c) if dp_c.is_a?(Numeric)
      end

      {
        temp: temp_f,
        condition: condition,
        timezone: '',
        precipitation: precipitation,
        wind_speed: wind_speed,
        wind_direction: wind_direction,
        wind_gusts: nil,
        pressure: pressure,
        humidity: humidity,
        dewpoint: dewpoint
      }
    end

    def metno_symbol_to_text(symbol_code)
      SaytimeWeather::WeatherConditions.from_metno_symbol(symbol_code)
    end
  end
end

