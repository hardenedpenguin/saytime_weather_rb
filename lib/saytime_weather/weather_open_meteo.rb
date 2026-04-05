# frozen_string_literal: true

module SaytimeWeather
  module WeatherOpenMeteo
    def fetch_weather_openmeteo(lat, lon)
      return nil if lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0

      current_params = "temperature_2m,weather_code,is_day"
      if @config['show_precipitation'] == 'YES' || @config['show_wind'] == 'YES' || @config['show_pressure'] == 'YES' || @config['show_humidity'] == 'YES'
        current_params += ",precipitation" if @config['show_precipitation'] == 'YES'
        current_params += ",wind_speed_10m,wind_direction_10m,wind_gusts_10m" if @config['show_wind'] == 'YES'
        current_params += ",pressure_msl" if @config['show_pressure'] == 'YES'
        current_params += ",relative_humidity_2m" if @config['show_humidity'] == 'YES'
      end

      url = SaytimeWeather::Endpoints.open_meteo_url(lat, lon, current_params)
      response = @http.get(url, SaytimeWeather::Network.timeout_long)
      return nil unless response

      data = safe_decode_json(response)
      return nil unless data && data['current']

      temp = data['current']['temperature_2m']
      code = data['current']['weather_code']
      is_day = data['current']['is_day'] || 1

      return nil unless temp.is_a?(Numeric)

      condition = weather_code_to_text(code, is_day)
      timezone = data['timezone'] || ''

      write_timezone_file(timezone)

      {
        temp: temp,
        condition: condition,
        timezone: timezone,
        precipitation: data['current']['precipitation'],
        wind_speed: data['current']['wind_speed_10m'],
        wind_direction: data['current']['wind_direction_10m'],
        wind_gusts: data['current']['wind_gusts_10m'],
        pressure: data['current']['pressure_msl'],
        humidity: data['current']['relative_humidity_2m']
      }
    end

    def weather_code_to_text(code, is_day = 1)
      return 'Sunny' if code == 1 && is_day == 1
      return 'Mainly Clear' if code == 1 && is_day == 0
      return 'Mostly Sunny' if code == 2 && is_day == 1
      return 'Partly Cloudy' if code == 2 && is_day == 0

      codes = {
        0 => 'Clear',
        3 => 'Overcast',
        45 => 'Foggy',
        48 => 'Foggy',
        51 => 'Light Drizzle',
        53 => 'Drizzle',
        55 => 'Heavy Drizzle',
        56 => 'Light Freezing Drizzle',
        57 => 'Freezing Drizzle',
        61 => 'Light Rain',
        63 => 'Rain',
        65 => 'Heavy Rain',
        66 => 'Light Freezing Rain',
        67 => 'Freezing Rain',
        71 => 'Light Snow',
        73 => 'Snow',
        75 => 'Heavy Snow',
        77 => 'Snow Grains',
        80 => 'Light Showers',
        81 => 'Showers',
        82 => 'Heavy Showers',
        85 => 'Light Snow Showers',
        86 => 'Snow Showers',
        95 => 'Thunderstorm',
        96 => 'Thunderstorm with Light Hail',
        99 => 'Thunderstorm with Hail'
      }

      codes[code] || 'Unknown'
    end
  end
end
