# frozen_string_literal: true

module SaytimeWeather
  module WeatherWeatherapi
    def weatherapi_key
      key = @config['weatherapi_key'].to_s.strip
      key = ENV['WEATHERAPI_KEY'].to_s.strip if key.empty?
      key.empty? ? nil : key
    end

    def weatherapi_available?
      !weatherapi_key.nil?
    end

    def weatherapi_direct_lookup?
      configured_provider == 'weatherapi' && weatherapi_available?
    end

    def fetch_weather_weatherapi(lat = nil, lon = nil, query: nil)
      key = weatherapi_key
      return nil unless key

      q = weatherapi_request_query(lat, lon, query)
      return nil unless q

      url = Endpoints.weatherapi_current_url(key, q)
      response = @http.get(url, Network.timeout_long)
      return nil unless response

      parse_weatherapi_response(safe_decode_json(response))
    end

    def weatherapi_request_query(lat, lon, query)
      q = query.to_s.strip
      return q unless q.empty?

      return nil unless lat.is_a?(Numeric) && lon.is_a?(Numeric)
      return nil if lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0

      format('%.4f,%.4f', lat, lon)
    end

    def weatherapi_query_for_location(location)
      loc = location.to_s.strip
      return nil if loc.empty?
      return nil if coordinate_literal?(loc)

      return "iata:#{loc.upcase}" if iata_code?(loc)
      return "metar:#{loc.upcase}" if icao_code?(loc)

      country_hint = geocode_country_hint(loc)
      if loc =~ /^\d{5}$/
        return loc if !country_hint || country_hint == 'us'

        return "#{loc},#{country_hint.upcase}"
      end

      if loc =~ /^\d{4}$/ && country_hint && country_hint != 'us'
        return "#{loc},#{country_hint.upcase}"
      end

      if loc =~ /^([A-Z]\d[A-Z])\s?\d[A-Z]\d$/i
        normalized = loc.upcase.gsub(/\s+/, '').sub(/^([A-Z]\d[A-Z])(\d[A-Z]\d)$/, '\1 \2')
        return "#{normalized},CA"
      end

      loc
    end

    def parse_weatherapi_response(data)
      return nil unless data.is_a?(Hash)
      return nil if data['error']

      cur = data['current']
      loc = data['location']
      return nil unless cur.is_a?(Hash) && loc.is_a?(Hash)

      temp_f = cur['temp_f']
      temp_f = temp_f.to_f if temp_f.is_a?(String)
      return nil unless temp_f.is_a?(Numeric)

      text = cur.dig('condition', 'text').to_s.strip
      condition = WeatherConditions.from_text(text) || text
      return nil if condition.empty?

      observation_time = loc['localtime'].to_s.strip.gsub(' ', 'T')
      timezone = loc['tz_id'].to_s.strip
      condition = weatherapi_condition_for_time(condition, cur['is_day'], timezone, observation_time)

      lat = loc['lat']
      lon = loc['lon']
      lat = lat.to_f if lat.is_a?(String) || lat.is_a?(Integer)
      lon = lon.to_f if lon.is_a?(String) || lon.is_a?(Integer)
      lat = nil unless lat.is_a?(Numeric)
      lon = nil unless lon.is_a?(Numeric)

      precipitation = nil
      if @config['show_precipitation'] == 'YES'
        pmm = cur['precip_mm']
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
        mb = cur['pressure_mb']
        mb = mb.to_f if mb.is_a?(String)
        pressure = mb if mb.is_a?(Numeric)
      end

      wind_speed = nil
      wind_direction = nil
      wind_gusts = nil
      if @config['show_wind'] == 'YES'
        mph = cur['wind_mph']
        mph = mph.to_f if mph.is_a?(String)
        wind_speed = mph_to_ms(mph) if mph.is_a?(Numeric)

        wd = cur['wind_degree']
        wd = wd.to_f if wd.is_a?(String)
        wind_direction = wd if wd.is_a?(Numeric)

        gust = cur['gust_mph']
        gust = gust.to_f if gust.is_a?(String)
        wind_gusts = mph_to_ms(gust) if gust.is_a?(Numeric)
      end

      {
        temp: temp_f,
        condition: condition,
        timezone: timezone,
        observation_time: observation_time,
        lat: lat,
        lon: lon,
        precipitation: precipitation,
        wind_speed: wind_speed,
        wind_direction: wind_direction,
        wind_gusts: wind_gusts,
        pressure: pressure,
        humidity: humidity
      }
    end

    def weatherapi_condition_for_time(condition, is_day, timezone, observation_time)
      case is_day
      when 0, '0'
        WeatherConditions.adjust_for_night(condition)
      when 1, '1'
        condition
      else
        WeatherConditions.apply_time_aware_night(condition, timezone: timezone, local_time: observation_time)
      end
    end

  end
end
