# frozen_string_literal: true

module SaytimeWeather
  module WeatherMetar
    def fetch_metar_weather(icao)
      icao = icao.upcase
      tlong = SaytimeWeather::Network.timeout_long

      metar = @http.get(SaytimeWeather::Endpoints.aviation_metar_url(icao), tlong)
      metar = metar.strip if metar

      unless metar && !metar.empty?
        response = @http.get(SaytimeWeather::Endpoints.noaa_metar_file_url(icao), tlong)
        if response
          lines = response.split("\n")
          metar = lines[1].strip if lines.length > 1
        end
      end

      return nil unless metar && !metar.empty?

      temp_f = parse_metar_temperature(metar)
      condition = parse_metar_condition(metar)

      [temp_f, condition]
    end

    def parse_metar_temperature(metar)
      if metar =~ /\s(M?\d{2})\/(M?\d{2})\s/
        temp_c_str = $1
        temp_c_str = temp_c_str.sub(/^M/, '-')
        temp_c_str = temp_c_str.sub(/^(-?)0+(\d)/, '\1\2')
        temp_c = temp_c_str.to_f
        temp_f = (temp_c * 9.0 / 5.0) + 32.0
        temp_f.round
      end
    end

    def parse_metar_condition(metar)
      return 'Thunderstorm' if metar =~ /\bTS\b/
      return 'Heavy Rain' if metar =~ /\+RA\b/
      return 'Rain' if metar =~ /(-|VC)?RA\b/
      return 'Light Rain' if metar =~ /-RA\b/
      return 'Drizzle' if metar =~ /DZ\b/
      return 'Snow' if metar =~ /SN\b/
      return 'Sleet' if metar =~ /PL\b/
      return 'Hail' if metar =~ /GR\b/
      return 'Foggy' if metar =~ /\bFG\b/
      return 'Mist' if metar =~ /BR\b/
      return 'Overcast' if metar =~ /\bOVC\d{3}\b/
      return 'Cloudy' if metar =~ /\bBKN\d{3}\b/
      return 'Partly Cloudy' if metar =~ /\bSCT\d{3}\b/
      return 'Clear' if metar =~ /\b(FEW\d{3}|CLR|SKC)\b/
      'Clear'
    end
  end
end
