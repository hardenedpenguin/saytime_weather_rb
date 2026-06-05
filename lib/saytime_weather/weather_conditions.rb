# frozen_string_literal: true

module SaytimeWeather
  # Normalizes free-text or provider-specific condition strings to canonical labels
  # used for display and wx/*.ulaw sound matching.
  module WeatherConditions
    module_function

    def from_text(text)
      return nil unless text && !text.to_s.empty?

      text = text.downcase
      return 'Thunderstorm' if text =~ /thunderstorm|thunder|t-storm/
      return 'Heavy Rain' if text =~ /heavy.*rain|rain.*heavy|torrential/
      return 'Heavy Snow' if text =~ /heavy.*snow|snow.*heavy/
      return 'Light Rain' if text =~ /light.*rain|rain.*light|drizzle/
      return 'Light Snow' if text =~ /light.*snow|snow.*light|flurries/
      return 'Rain' if text =~ /\brain\b/
      return 'Snow' if text =~ /\bsnow\b/
      return 'Sleet' if text =~ /sleet|freezing.*rain|ice.*pellets/
      return 'Hail' if text =~ /\bhail\b/
      return 'Foggy' if text =~ /\bfog\b|\bmist\b/
      return 'Overcast' if text =~ /overcast|cloudy.*cloudy/
      return 'Partly Cloudy' if text =~ /partly.*cloud|partly.*sun|mostly.*cloud|mostly.*clear/
      return 'Cloudy' if text =~ /\bcloudy\b/
      return 'Mostly Sunny' if text =~ /mostly.*sun/
      return 'Sunny' if text =~ /\bsunny\b|clear.*sun|sun.*clear/
      return 'Clear' if text =~ /\bclear\b/

      'Clear'
    end

    # NWS and similar providers may still say "sunny" in text while the icon is /night/.
    def adjust_for_night(condition)
      case condition
      when 'Sunny' then 'Mainly Clear'
      when 'Mostly Sunny' then 'Partly Cloudy'
      else condition
      end
    end

    def from_metno_symbol(symbol_code)
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

    def from_seventimer(code)
      return nil unless code

      c = code.to_s.downcase
      return 'Thunderstorm' if c.start_with?('ts')
      return 'Sleet' if c.include?('rainsnow')
      return 'Light Rain' if c.start_with?('lightrain') || c.start_with?('oshower') || c.start_with?('ishower')
      return 'Rain' if c.start_with?('rain')
      return 'Light Snow' if c.start_with?('lightsnow')
      return 'Snow' if c.start_with?('snow')
      return 'Foggy' if c.start_with?('humid')
      return 'Overcast' if c.start_with?('cloudy')
      return 'Cloudy' if c.start_with?('mcloudy')
      return 'Partly Cloudy' if c.start_with?('pcloudy')
      return 'Clear' if c.start_with?('clear')

      nil
    end

    def from_metar(metar)
      return 'Thunderstorm' if metar =~ /\bTS\b/
      return 'Heavy Rain' if metar =~ /\+RA\b/
      return 'Light Rain' if metar =~ /-RA\b/
      return 'Rain' if metar =~ /(-|VC)?RA\b/
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
