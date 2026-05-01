# frozen_string_literal: true

module SaytimeWeather
  module WeatherMetNo
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
      if @config['show_precipitation'] == 'YES' && ts['data']['next_1_hours'] && ts['data']['next_1_hours']['details']
        pmm = ts['data']['next_1_hours']['details']['precipitation_amount']
        precipitation = pmm if pmm.is_a?(Numeric)
      end

      wind_speed = details['wind_speed']
      wind_speed = nil unless wind_speed.is_a?(Numeric)

      wind_direction = details['wind_from_direction']
      wind_direction = nil unless wind_direction.is_a?(Numeric)

      pressure = details['air_pressure_at_sea_level']
      pressure = nil unless pressure.is_a?(Numeric)

      humidity = details['relative_humidity']
      humidity = nil unless humidity.is_a?(Numeric)

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

    def metno_symbol_to_text(symbol_code)
      return nil unless symbol_code && !symbol_code.to_s.empty?

      s = symbol_code.to_s.downcase
      return 'Thunderstorm' if s.include?('thunder')
      return 'Sleet' if s.include?('sleet')
      return 'Foggy' if s.include?('fog')
      return 'Heavy Snow' if s.include?('heavysnow')
      return 'Light Snow' if s.include?('lightsnow')
      return 'Snow' if s.include?('snow')
      return 'Heavy Rain' if s.include?('heavyrain')
      return 'Light Rain' if s.include?('lightrain')
      return 'Rain' if s.include?('rain')
      return 'Overcast' if s.include?('overcast')
      return 'Cloudy' if s.include?('cloudy')
      return 'Partly Cloudy' if s.include?('partlycloudy')
      return 'Mostly Sunny' if s.include?('fair')
      return 'Clear' if s.include?('clearsky')

      nil
    end
  end
end

