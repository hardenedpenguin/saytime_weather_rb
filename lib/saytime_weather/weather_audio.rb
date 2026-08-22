# frozen_string_literal: true

require 'json'

module SaytimeWeather
  module WeatherAudio
    WIND_DIRECTION_FILES = {
      'N' => 'north.ulaw',
      'NNE' => 'north-northeast.ulaw',
      'NE' => 'northeast.ulaw',
      'ENE' => 'east-northeast.ulaw',
      'E' => 'east.ulaw',
      'ESE' => 'east-southeast.ulaw',
      'SE' => 'southeast.ulaw',
      'SSE' => 'south-southeast.ulaw',
      'S' => 'south.ulaw',
      'SSW' => 'south-southwest.ulaw',
      'SW' => 'southwest.ulaw',
      'WSW' => 'west-southwest.ulaw',
      'W' => 'west.ulaw',
      'WNW' => 'west-northwest.ulaw',
      'NW' => 'northwest.ulaw',
      'NNW' => 'north-northwest.ulaw'
    }.freeze

    def wx_sound(sound_dir, name)
      "#{sound_dir}/wx/#{name}"
    end

    def build_weather_extras_audio(extras, sound_dir, temp_mode)
      return '' unless extras.is_a?(Array) && extras.any?

      files = ''
      extras.each do |segment|
        files += build_weather_extra_segment(segment, sound_dir, temp_mode)
      end
      files
    end

    def build_weather_extra_segment(segment, sound_dir, temp_mode)
      case segment['k']
      when 'humidity'
        build_humidity_audio(segment['v'], sound_dir)
      when 'feels_like', 'dewpoint'
        build_temperature_field_audio(segment['k'], segment['v'], sound_dir)
      when 'wind'
        build_wind_audio(segment, sound_dir, temp_mode)
      when 'pressure'
        build_pressure_audio(segment['v'], sound_dir, temp_mode)
      when 'precip'
        build_precipitation_audio(segment['v'], sound_dir, temp_mode)
      when 'uv'
        build_uv_audio(segment['v'], sound_dir)
      when 'visibility'
        build_visibility_audio(segment['v'], sound_dir, temp_mode)
      else
        ''
      end
    end

    def build_temperature_field_audio(field_key, value, sound_dir)
      return '' unless value.is_a?(Numeric)

      label = field_key == 'feels_like' ? 'feels-like.ulaw' : 'dewpoint.ulaw'
      files = add_sound_file(wx_sound(sound_dir, label))
      files + build_signed_integer_audio(value.round, sound_dir) +
        add_sound_file(wx_sound(sound_dir, 'degrees.ulaw'))
    end

    def build_humidity_audio(value, sound_dir)
      return '' unless value.is_a?(Numeric)

      add_sound_file(wx_sound(sound_dir, 'humidity.ulaw')) +
        format_number(value.round, sound_dir) +
        add_sound_file(wx_sound(sound_dir, 'percent.ulaw'))
    end

    def build_wind_audio(segment, sound_dir, temp_mode)
      speed = segment['speed']
      return '' unless speed.is_a?(Numeric) && speed.positive?

      unit_file = temp_mode == 'F' ? 'miles-per-hour.ulaw' : 'kilometers-per-hour.ulaw'
      files = add_sound_file(wx_sound(sound_dir, 'wind.ulaw')) +
              format_number(speed.round, sound_dir) +
              add_sound_file(wx_sound(sound_dir, unit_file))

      dir = segment['dir']
      if dir.is_a?(String) && (dir_file = WIND_DIRECTION_FILES[dir])
        files += add_sound_file(wx_sound(sound_dir, dir_file))
      end

      gust = segment['gust']
      if gust.is_a?(Numeric) && gust > speed
        files += add_sound_file(wx_sound(sound_dir, 'gust.ulaw')) +
                 format_number(gust.round, sound_dir) +
                 add_sound_file(wx_sound(sound_dir, unit_file))
      end

      files
    end

    def build_pressure_audio(value, sound_dir, temp_mode)
      return '' unless value.is_a?(Numeric)

      files = add_sound_file(wx_sound(sound_dir, 'pressure.ulaw'))
      if temp_mode == 'F'
        files + format_decimal(value, sound_dir, decimal_places: 2) +
          add_sound_file(wx_sound(sound_dir, 'inches-of-mercury.ulaw'))
      else
        files + format_number(value.round, sound_dir) +
          add_sound_file(wx_sound(sound_dir, 'hectopascals.ulaw'))
      end
    end

    def build_precipitation_audio(value, sound_dir, temp_mode)
      return '' unless value.is_a?(Numeric) && value.positive?

      files = add_sound_file(wx_sound(sound_dir, 'precipitation.ulaw'))
      if temp_mode == 'F'
        files + format_decimal(value, sound_dir, decimal_places: 2) +
          add_sound_file(wx_sound(sound_dir, 'inches.ulaw'))
      else
        files + format_decimal(value, sound_dir, decimal_places: 2) +
          add_sound_file(wx_sound(sound_dir, 'millimeters.ulaw'))
      end
    end

    def build_uv_audio(value, sound_dir)
      return '' unless value.is_a?(Numeric)

      add_sound_file(wx_sound(sound_dir, 'uv-index.ulaw')) +
        format_number(value.round, sound_dir)
    end

    def build_visibility_audio(value, sound_dir, temp_mode)
      return '' unless value.is_a?(Numeric) && !value.negative?

      unit_file = temp_mode == 'F' ? 'miles.ulaw' : 'kilometers.ulaw'
      add_sound_file(wx_sound(sound_dir, 'visibility.ulaw')) +
        format_decimal(value, sound_dir, decimal_places: 1) +
        add_sound_file(wx_sound(sound_dir, unit_file))
    end

    def build_signed_integer_audio(value, sound_dir)
      files = ''
      if value.negative?
        files += add_sound_file("#{sound_dir}/digits/minus.ulaw")
        value = value.abs
      end
      files + format_number(value, sound_dir)
    end

    def format_decimal(value, sound_dir, decimal_places: 1)
      rounded = value.round(decimal_places)
      whole = rounded.to_i
      frac = ((rounded - whole).abs * (10**decimal_places)).round

      files = format_number(whole, sound_dir)
      return files if frac.zero?

      files + add_sound_file(wx_sound(sound_dir, 'point.ulaw')) + format_fractional_digits(frac, decimal_places, sound_dir)
    end

    def format_fractional_digits(frac, decimal_places, sound_dir)
      digits = frac.to_s.rjust(decimal_places, '0').each_char.map(&:to_i)
      files = ''
      digits.each do |digit|
        files += add_sound_file("#{sound_dir}/digits/#{digit}.ulaw")
      end
      files
    end

    def read_weather_extras_file(path)
      return [] unless path && File.exist?(path)

      data = JSON.parse(File.read(path))
      data.is_a?(Array) ? data : []
    rescue JSON::ParserError
      []
    end
  end
end
