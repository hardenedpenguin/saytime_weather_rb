# frozen_string_literal: true

module SaytimeWeather
  module WeatherWttr
    def fetch_weather_wttr(lat, lon)
      return nil if lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0

      url = SaytimeWeather::Endpoints.wttr_in_url("#{lat},#{lon}")
      response = @http.get(url, SaytimeWeather::Network.timeout_long)
      return nil unless response

      data = safe_decode_json(response)
      return nil unless data && data['current_condition'].is_a?(Array) && data['current_condition'][0].is_a?(Hash)

      cur = data['current_condition'][0]
      temp_f = cur['temp_F'] || cur['FeelsLikeF']
      temp_f = temp_f.to_f if temp_f.is_a?(String)
      return nil unless temp_f.is_a?(Numeric)

      desc = nil
      if cur['weatherDesc'].is_a?(Array) && cur['weatherDesc'][0].is_a?(Hash)
        desc = cur['weatherDesc'][0]['value']
      end
      condition = wttr_text_to_condition(desc)
      return nil unless condition

      precipitation = nil
      if @config['show_precipitation'] == 'YES'
        pmm = cur['precipMM']
        pmm = pmm.to_f if pmm.is_a?(String)
        precipitation = pmm if pmm.is_a?(Numeric)
      end

      humidity = nil
      if @config['show_humidity'] == 'YES'
        rh = cur['humidity']
        rh = rh.to_f if rh.is_a?(String)
        humidity = rh if rh.is_a?(Numeric)
      end

      pressure = nil
      if @config['show_pressure'] == 'YES'
        press = cur['pressure']
        press = press.to_f if press.is_a?(String)
        pressure = press if press.is_a?(Numeric)
      end

      wind_speed = nil
      wind_direction = nil
      if @config['show_wind'] == 'YES'
        mph = cur['windspeedMiles']
        mph = mph.to_f if mph.is_a?(String)
        wind_speed = mph_to_ms(mph) if mph.is_a?(Numeric)

        wd = cur['winddirDegree']
        wd = wd.to_f if wd.is_a?(String)
        wind_direction = wd if wd.is_a?(Numeric)
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
        humidity: humidity
      }
    end

    def mph_to_ms(mph)
      return nil unless mph && mph.is_a?(Numeric)
      mph / 2.23694
    end

    def wttr_text_to_condition(text)
      return nil unless text && !text.to_s.empty?

      # Reuse the NWS text parser semantics where possible to keep conditions consistent.
      parse_nws_condition(text)
    end
  end
end

