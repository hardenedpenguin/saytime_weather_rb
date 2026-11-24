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

    DEFAULT_CACHE_DIR = '/var/cache/saytime-weather-rb'

    # Persistent cache directory (geocode, timezone, airports, GPS fix).
    # Order: SAYTIME_CACHE_DIR, the package cache dir (created by postinst, owned by
    # asterisk so both root cron and asterisk DTMF runs can update it), then a per-user
    # directory under tmp_dir. A per-user tmp directory that is not owned by us (for
    # example one pre-created by another user) is never used; caching then falls back
    # to the current run's private scratch directory.
    def cache_dir
      env = ENV['SAYTIME_CACHE_DIR'].to_s.strip
      return env unless env.empty?
      return DEFAULT_CACHE_DIR if usable_cache_dir?(DEFAULT_CACHE_DIR)

      per_user = File.join(tmp_dir, "saytime-weather-cache-#{Process.uid}")
      begin
        Dir.mkdir(per_user, 0o700) unless File.exist?(per_user) || File.symlink?(per_user)
      rescue SystemCallError
        nil
      end
      return per_user if usable_cache_dir?(per_user) && File.stat(per_user).owned?

      SaytimeWeather::RunContext.run_dir
    end

    def usable_cache_dir?(dir)
      File.directory?(dir) && !File.symlink?(dir) && File.writable?(dir)
    rescue SystemCallError
      false
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
      File.join(cache_dir, 'ourairports.csv')
    end

    def geocode_cache_path(key)
      safe = key.to_s.gsub(/[^a-zA-Z0-9._-]/, '_')
      File.join(cache_dir, "geocode-#{safe}.json")
    end

    def timezone_cache_path(lat, lon)
      File.join(cache_dir, "timezone-#{lat.round(2)}_#{lon.round(2)}.json")
    end

    def airports_maps_cache_path
      File.join(cache_dir, 'airports-maps.json')
    end

    def gps_fix_cache_path
      File.join(cache_dir, 'gps-fix.json')
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
