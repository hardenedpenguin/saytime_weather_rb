# frozen_string_literal: true

module SaytimeWeather
  module Weather7Timer
    def fetch_weather_7timer(lat, lon)
      return nil if lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0

      url = SaytimeWeather::Endpoints.seventimer_civil_url(lat.round(3), lon.round(3))
      response = @http.get(url, SaytimeWeather::Network.timeout_long)
      return nil unless response

      data = safe_decode_json(response)
      return nil unless data && data['dataseries'].is_a?(Array) && data['dataseries'][0].is_a?(Hash)

      cur = data['dataseries'][0]

      temp_c = cur['temp2m']
      return nil unless temp_c.is_a?(Numeric)
      temp_f = (temp_c * 9.0 / 5.0) + 32.0

      condition = seventimer_weather_to_condition(cur['weather'])
      return nil unless condition

      precipitation = nil
      if @config['show_precipitation'] == 'YES'
        precipitation = seventimer_precip_amount_to_mm(cur['prec_amount'])
      end

      humidity = nil
      if @config['show_humidity'] == 'YES'
        rh = cur['rh2m']
        if rh.is_a?(String) && rh.end_with?('%')
          humidity = rh.delete('%').to_f
        elsif rh.is_a?(Numeric)
          humidity = rh
        end
      end

      wind_speed = nil
      wind_direction = nil
      if @config['show_wind'] == 'YES' && cur['wind10m'].is_a?(Hash)
        wind_speed = seventimer_wind_speed_to_ms(cur['wind10m']['speed'])
        wind_direction = seventimer_wind_dir_to_degrees(cur['wind10m']['direction'])
      end

      {
        temp: temp_f,
        condition: condition,
        timezone: '',
        precipitation: precipitation,
        wind_speed: wind_speed,
        wind_direction: wind_direction,
        wind_gusts: nil,
        pressure: nil,
        humidity: humidity
      }
    end

    def seventimer_weather_to_condition(code)
      return nil unless code

      c = code.to_s.downcase
      return 'Thunderstorm' if c.start_with?('ts')
      return 'Sleet' if c.include?('rainsnow')
      return 'Light Rain' if c.start_with?('lightrain') || c.start_with?('oshower') || c.start_with?('ishower')
      return 'Rain' if c.start_with?('rain')
      return 'Light Snow' if c.start_with?('lightsnow')
      return 'Snow' if c.start_with?('snow')
      return 'Foggy' if c.start_with?('humid')
      return 'Overcast' if c.start_with?('cloudy')
      return 'Cloudy' if c.start_with?('mcloudy')
      return 'Partly Cloudy' if c.start_with?('pcloudy')
      return 'Clear' if c.start_with?('clear')

      nil
    end

    def seventimer_wind_dir_to_degrees(dir)
      return nil unless dir

      map = {
        'N' => 0.0, 'NE' => 45.0, 'E' => 90.0, 'SE' => 135.0,
        'S' => 180.0, 'SW' => 225.0, 'W' => 270.0, 'NW' => 315.0
      }
      map[dir.to_s.upcase]
    end

    # 7Timer: 1..8 corresponds to ranges; use midpoints for a stable numeric.
    def seventimer_wind_speed_to_ms(level)
      return nil unless level && level.is_a?(Numeric)

      case level.to_i
      when 1 then 0.0
      when 2 then (0.3 + 3.4) / 2.0
      when 3 then (3.4 + 8.0) / 2.0
      when 4 then (8.0 + 10.8) / 2.0
      when 5 then (10.8 + 17.2) / 2.0
      when 6 then (17.2 + 24.5) / 2.0
      when 7 then (24.5 + 32.6) / 2.0
      when 8 then 33.0
      else
        nil
      end
    end

    # 7Timer precipitation amount is an index; map to mm/hr midpoint-ish.
    def seventimer_precip_amount_to_mm(level)
      return nil unless level && level.is_a?(Numeric)

      case level.to_i
      when 0 then 0.0
      when 1 then 0.125
      when 2 then 0.625
      when 3 then 2.5
      when 4 then 7.0
      when 5 then 13.0
      when 6 then 23.0
      when 7 then 40.0
      when 8 then 62.5
      when 9 then 80.0
      else
        nil
      end
    end
  end
end

