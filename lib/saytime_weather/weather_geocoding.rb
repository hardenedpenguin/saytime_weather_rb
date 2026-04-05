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

    def postal_to_coordinates(postal)
      postal_uc = postal.upcase.gsub(/[^A-Z0-9]/, '')
      if (coords = special_locations_table[postal_uc])
        return coords
      end

      ndelay = SaytimeWeather::Network.nominatim_delay
      sleep(ndelay) if ndelay > 0

      url = if postal =~ /^\d{5}$/
              SaytimeWeather::Endpoints.nominatim_postal_url(postal, country: @config['default_country'].downcase)
            elsif postal =~ /^([A-Z]\d[A-Z])\s?\d[A-Z]\d$/i
              normalized = postal.upcase.gsub(/\s+/, '').sub(/^([A-Z]\d[A-Z])(\d[A-Z]\d)$/, '\1 \2')
              SaytimeWeather::Endpoints.nominatim_postal_url(normalized, country: 'ca')
            else
              SaytimeWeather::Endpoints.nominatim_postal_url(postal)
            end

      response = @http.get(url, SaytimeWeather::Network.timeout_short)
      return nil unless response

      data = safe_decode_json(response)
      return nil unless data.is_a?(Array) && data.any?

      first_result = data[0]
      return nil unless first_result.is_a?(Hash) && first_result['lat'] && first_result['lon']

      lat = first_result['lat'].to_f
      lon = first_result['lon'].to_f

      return nil if lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0

      [lat, lon]
    end
  end
end
