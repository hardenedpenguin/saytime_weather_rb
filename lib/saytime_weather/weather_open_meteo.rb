# frozen_string_literal: true

module SaytimeWeather
  module WeatherOpenMeteo
    def read_timezone_cache(lat, lon)
      path = Paths.timezone_cache_path(lat, lon)
      data = Cache.read_json(path, Network.timezone_cache_max_age)
      tz = data && data['timezone']
      tz if tz && !tz.to_s.empty?
    end

    def write_timezone_cache(lat, lon, timezone)
      return unless timezone && !timezone.to_s.empty?

      Cache.write_json(Paths.timezone_cache_path(lat, lon), { 'timezone' => timezone })
    end

    def open_meteo_current_params(include_extras: false)
      params = 'temperature_2m,weather_code,is_day'
      return params unless include_extras

      if @config['show_precipitation'] == 'YES' || @config['show_wind'] == 'YES' ||
         @config['show_pressure'] == 'YES' || @config['show_humidity'] == 'YES'
        params += ',precipitation' if @config['show_precipitation'] == 'YES'
        params += ',wind_speed_10m,wind_direction_10m,wind_gusts_10m' if @config['show_wind'] == 'YES'
        params += ',pressure_msl' if @config['show_pressure'] == 'YES'
        params += ',relative_humidity_2m' if @config['show_humidity'] == 'YES'
      end
      params
    end

    def parse_openmeteo_response(data)
      return nil unless data && data['current']

      temp = data['current']['temperature_2m']
      code = data['current']['weather_code']
      local_time = data['current']['time'].to_s
      is_day = open_meteo_is_day(data['current']['is_day'])
      return nil unless temp.is_a?(Numeric)

      condition = weather_code_to_text(code, is_day, local_time: local_time)
      return nil unless WeatherNumeric.valid_condition?(condition)

      {
        temp: temp,
        condition: condition,
        timezone: data['timezone'] || '',
        observation_time: local_time,
        precipitation: data['current']['precipitation'],
        wind_speed: data['current']['wind_speed_10m'],
        wind_direction: data['current']['wind_direction_10m'],
        wind_gusts: data['current']['wind_gusts_10m'],
        pressure: data['current']['pressure_msl'],
        humidity: data['current']['relative_humidity_2m']
      }
    end

    def fetch_openmeteo(lat, lon, include_extras: false)
      return nil if lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0

      params = open_meteo_current_params(include_extras: include_extras)
      url = Endpoints.open_meteo_url(lat, lon, params)
      response = @http.get(url, Network.timeout_long)
      return nil unless response

      parse_openmeteo_response(safe_decode_json(response))
    end

    def fetch_timezone_openmeteo(lat, lon)
      return nil if lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0

      if (cached = read_timezone_cache(lat, lon))
        write_timezone_file(cached)
        return cached
      end

      url = Endpoints.open_meteo_url(lat, lon, 'temperature_2m')
      response = @http.get(url, Network.timeout_long)
      return nil unless response

      data = safe_decode_json(response)
      timezone = data && data['timezone']
      if timezone && !timezone.empty?
        write_timezone_file(timezone)
        write_timezone_cache(lat, lon, timezone)
      end
      timezone
    end

    def fetch_weather_openmeteo(lat, lon)
      data = fetch_openmeteo(lat, lon, include_extras: true)
      return nil unless data

      write_timezone_file(data[:timezone]) if data[:timezone] && !data[:timezone].empty?
      write_timezone_cache(lat, lon, data[:timezone]) if data[:timezone] && !data[:timezone].empty?
      data
    end

    def open_meteo_is_day(raw)
      return 0 if raw.to_s == '0' || raw == 0
      return 1 if raw.to_s == '1' || raw == 1

      1
    end

    def open_meteo_evening?(local_time)
      m = local_time.to_s.match(/T(\d{2}):(\d{2})/)
      return false unless m

      m[1].to_i >= 20
    end

    def weather_code_to_text(code, is_day = 1, local_time: nil)
      night = is_day == 0 || open_meteo_evening?(local_time)
      return 'Sunny' if code == 1 && !night
      return 'Mainly Clear' if code == 1 && night
      return 'Mostly Sunny' if code == 2 && !night
      return 'Partly Cloudy' if code == 2 && night

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

      codes[code]
    end
  end
end
