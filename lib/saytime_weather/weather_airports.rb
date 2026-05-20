# frozen_string_literal: true

require 'csv'

module SaytimeWeather
  module WeatherAirports
    def iata_code?(code)
      return false unless code =~ /^[A-Z]{3}$/i
      true
    end

    def refresh_airports_cache_if_stale
      cache = SaytimeWeather::Paths.airports_cache_path
      max_age = SaytimeWeather::Network.airports_cache_max_age
      stale = !File.exist?(cache) || (Time.now - File.mtime(cache)) > max_age
      return unless stale

      body = @http.get(SaytimeWeather::Network.airports_data_url, SaytimeWeather::Network.timeout_long,
                       SaytimeWeather::Endpoints::DEFAULT_HTTP_UA)
      return if body.nil? || body.empty?

      tmp = "#{cache}.part"
      File.write(tmp, body)
      File.rename(tmp, cache)
    rescue => e
      warn("Airports data download failed: #{e.message}") if @options[:verbose]
    end

    def ensure_airports_loaded
      return if @airports_loaded

      @airport_iata_map, @airport_icao_coords = load_airports_csv_from_disk
      @airports_loaded = true
    end

    def load_airports_csv_from_disk
      refresh_airports_cache_if_stale
      cache = SaytimeWeather::Paths.airports_cache_path
      return [{}, {}] unless File.exist?(cache)

      iata_map = {}
      icao_coords = {}
      CSV.foreach(cache, headers: true) do |row|
        icao = row['icao_code']&.strip&.upcase
        next if icao.nil? || icao.empty?

        lat = row['latitude_deg']&.to_f
        lon = row['longitude_deg']&.to_f
        if lat && lon && lat >= -90.0 && lat <= 90.0 && lon >= -180.0 && lon <= 180.0
          icao_coords[icao] = [lat, lon]
        end

        iata = row['iata_code']&.strip&.upcase
        next unless iata && iata.length == 3 && iata.match?(/\A[A-Z]{3}\z/)

        iata_map[iata] = icao
      end
      [iata_map, icao_coords]
    rescue => e
      warn("Failed to parse airports data: #{e.message}") if @options[:verbose]
      [{}, {}]
    end

    def airport_iata_to_icao_map
      ensure_airports_loaded
      @airport_iata_map
    end

    def airport_coordinates(icao)
      ensure_airports_loaded
      @airport_icao_coords[icao.to_s.upcase]
    end

    def iata_to_icao(iata)
      iata = iata.upcase
      icao = airport_iata_to_icao_map[iata]
      return icao if icao && !icao.empty?

      "K#{iata}"
    end

    def icao_code?(code)
      return false unless code =~ /^[A-Z]{4}$/i
      prefix = code[0].upcase
      %w[A B C D E F G H I J K L M N O P Q R S T U V W Y Z].include?(prefix)
    end
  end
end
