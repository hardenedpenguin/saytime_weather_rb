# frozen_string_literal: true

module SaytimeWeather
  module WeatherGeocoding
    def special_locations_table
      @special_locations_table ||= load_special_locations_json
    end

    def load_special_locations_json
      path = SaytimeWeather::Paths.special_locations_file
      return {} unless File.exist?(path)

      raw = JSON.parse(File.read(path))
      out = {}
      raw.each do |k, v|
        next unless k.is_a?(String) && v.is_a?(Array) && v.length >= 2

        out[k.upcase.gsub(/[^A-Z0-9]/, '')] = [v[0].to_f, v[1].to_f]
      end
      out
    rescue => e
      warn("Failed to load special_locations.json: #{e.message}")
      {}
    end

    def geocode_cache_key(postal, country_hint)
      "#{country_hint || 'intl'}-#{postal.upcase.gsub(/[^A-Z0-9]/, '')}"
    end

    def read_geocode_cache(postal, country_hint)
      key = geocode_cache_key(postal, country_hint)
      path = SaytimeWeather::Paths.geocode_cache_path(key)
      data = Cache.read_json(path, Network.geocode_cache_max_age)
      return nil unless data && data['lat'] && data['lon']

      [data['lat'].to_f, data['lon'].to_f]
    end

    def write_geocode_cache(postal, country_hint, lat, lon)
      key = geocode_cache_key(postal, country_hint)
      path = SaytimeWeather::Paths.geocode_cache_path(key)
      Cache.write_json(path, { 'lat' => lat, 'lon' => lon })
    end

    def postal_to_coordinates(postal)
      postal_uc = postal.upcase.gsub(/[^A-Z0-9]/, '')
      if (coords = special_locations_table[postal_uc])
        return coords
      end

      country_hint = geocode_country_hint(postal)
      if (cached = read_geocode_cache(postal, country_hint))
        return cached
      end

      ndelay = Network.nominatim_delay
      sleep(ndelay) if ndelay > 0

      url = geocode_nominatim_url(postal, country_hint)
      response = @http.get(url, Network.timeout_short)
      return nil unless response

      data = safe_decode_json(response)
      return nil unless data.is_a?(Array) && data.any?

      first_result = data[0]
      return nil unless first_result.is_a?(Hash) && first_result['lat'] && first_result['lon']

      lat = first_result['lat'].to_f
      lon = first_result['lon'].to_f

      return nil if lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0

      write_geocode_cache(postal, country_hint, lat, lon)
      [lat, lon]
    end

    def geocode_country_hint(postal)
      if postal =~ /^\d{5}$/
        @config['default_country'].downcase
      elsif postal =~ /^([A-Z]\d[A-Z])\s?\d[A-Z]\d$/i
        'ca'
      end
    end

    def geocode_nominatim_url(postal, country_hint)
      if postal =~ /^\d{5}$/
        Endpoints.nominatim_postal_url(postal, country: country_hint || @config['default_country'].downcase)
      elsif postal =~ /^([A-Z]\d[A-Z])\s?\d[A-Z]\d$/i
        normalized = postal.upcase.gsub(/\s+/, '').sub(/^([A-Z]\d[A-Z])(\d[A-Z]\d)$/, '\1 \2')
        Endpoints.nominatim_postal_url(normalized, country: 'ca')
      else
        Endpoints.nominatim_postal_url(postal)
      end
    end

    COORDINATE_LITERAL_RE = /\A(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\z/

    def coordinate_literal?(location)
      location.to_s.match?(COORDINATE_LITERAL_RE)
    end

    def parse_coordinate_literal(location)
      m = location.to_s.match(COORDINATE_LITERAL_RE)
      return nil unless m

      lat = m[1].to_f
      lon = m[2].to_f
      return nil if lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0

      [lat, lon]
    end

    def valid_location_format?(location)
      return true if location.nil? || location.to_s.empty?
      return true if coordinate_literal?(location)

      location.to_s.match?(/\A[a-zA-Z0-9\s\-_.]+\z/)
    end
  end
end
