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

    def build_airport_iata_map
      refresh_airports_cache_if_stale
      cache = SaytimeWeather::Paths.airports_cache_path
      return {} unless File.exist?(cache)

      map = {}
      CSV.foreach(cache, headers: true) do |row|
        iata = row['iata_code']&.strip&.upcase
        next unless iata && iata.length == 3 && iata.match?(/\A[A-Z]{3}\z/)

        icao = row['icao_code']&.strip&.upcase
        next if icao.nil? || icao.empty?

        map[iata] = icao
      end
      map
    rescue => e
      warn("Failed to parse airports data: #{e.message}") if @options[:verbose]
      {}
    end

    def airport_iata_to_icao_map
      @airport_iata_map ||= build_airport_iata_map
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
