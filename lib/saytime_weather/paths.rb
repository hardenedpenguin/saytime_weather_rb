# frozen_string_literal: true

module SaytimeWeather
  module Paths
    module_function

    def tmp_dir
      ENV.fetch('SAYTIME_TMP', '/tmp')
    end

    def config_path
      ENV.fetch('WEATHER_CONFIG', '/etc/asterisk/local/weather.ini')
    end

    def asterisk_sounds_en
      ENV.fetch('SAYTIME_SOUND_ROOT', '/usr/share/asterisk/sounds/en')
    end

    def weather_sound_dir
      File.join(asterisk_sounds_en, 'wx')
    end

    def asterisk_bin
      ENV.fetch('ASTERISK_BIN', '/usr/sbin/asterisk')
    end

    def special_locations_file
      File.join(SaytimeWeather.root, 'data', 'special_locations.json')
    end

    def airports_cache_path
      File.join(tmp_dir, 'saytime-weather-ourairports.csv')
    end

    def geocode_cache_path(key)
      safe = key.to_s.gsub(/[^a-zA-Z0-9._-]/, '_')
      File.join(tmp_dir, "saytime-geocode-#{safe}.json")
    end

    def timezone_cache_path(lat, lon)
      File.join(tmp_dir, "saytime-timezone-#{lat.round(2)}_#{lon.round(2)}.json")
    end

    def airports_maps_cache_path
      File.join(tmp_dir, 'saytime-weather-airports-maps.json')
    end

    def gps_fix_cache_path
      File.join(tmp_dir, 'saytime-gps-fix.json')
    end

    def weather_script_path
      File.join(SaytimeWeather.root, 'weather.rb')
    end

    # Prefixes allowed for combined sound file paths (saytime safety check)
    def sound_path_prefixes(custom_dir = nil)
      en = asterisk_sounds_en
      sounds_parent = File.expand_path('..', en)
      list = [
        "#{sounds_parent}/",
        "#{en}/",
        "#{File.expand_path(tmp_dir)}/"
      ]
      list << "#{File.expand_path(custom_dir.to_s)}/" if custom_dir && !custom_dir.to_s.empty?
      list
    end
  end
end
