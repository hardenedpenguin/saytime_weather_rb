# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'tmpdir'
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'saytime_weather'
SaytimeWeather.root = File.expand_path('..', __dir__)

class GeocodingConfigTest
  PARIS = [48.8566, 2.3522]
  DALLAS = [32.7767, -96.7970]
  SYDNEY = [-33.8700, 151.2073]
  ALBANIA_2000 = [41.3152, 19.4466]

  def assert_equal(expected, actual, msg = nil)
    return if expected == actual

    raise "#{msg || 'assertion'}: expected #{expected.inspect}, got #{actual.inspect}"
  end

  def with_temp_config(default_country: 'us')
    Dir.mktmpdir('saytime-geocode-test') do |dir|
      ini = File.join(dir, 'weather.ini')
      File.write(ini, <<~INI)
        [weather]
        default_country = #{default_country}
        weather_provider = openmeteo
        weather_provider_random = NO
      INI
      yield ini, dir
    end
  end

  def test_cli_country_overrides_ini
    with_temp_config(default_country: 'us') do |ini, _dir|
      script = SaytimeWeather::WeatherScript.new(
        options: { config_file: ini, default_country: 'fr', verbose: true }
      )
      assert_equal('fr', script.config['default_country'], 'CLI -d should override ini')
      assert_equal('fr', script.send(:geocode_country_hint, '75001'), '5-digit postal uses overridden country')
    end
  end

  def test_geocode_cache_respects_country_override
    with_temp_config(default_country: 'us') do |ini, dir|
      prev_tmp = ENV['SAYTIME_TMP']
      ENV['SAYTIME_TMP'] = dir
      begin
        write_geocode_cache(dir, 'us', '75001', *DALLAS)
        write_geocode_cache(dir, 'fr', '75001', *PARIS)

        us_script = SaytimeWeather::WeatherScript.new(options: { config_file: ini })
        fr_script = SaytimeWeather::WeatherScript.new(
          options: { config_file: ini, default_country: 'fr' }
        )

        us_coords = us_script.send(:postal_to_coordinates, '75001')
        fr_coords = fr_script.send(:postal_to_coordinates, '75001')

        assert_equal(DALLAS, us_coords, '75001 with ini us should resolve to Dallas cache')
        assert_equal(PARIS, fr_coords, '75001 with -d fr should resolve to Paris cache')
      ensure
        if prev_tmp
          ENV['SAYTIME_TMP'] = prev_tmp
        else
          ENV.delete('SAYTIME_TMP')
        end
      end
    end
  end

  def write_geocode_cache(tmp_dir, country, postal, lat, lon)
    key = "#{country}-#{postal}"
    safe = key.gsub(/[^a-zA-Z0-9._-]/, '_')
    path = File.join(tmp_dir, "saytime-geocode-#{safe}.json")
    File.write(path, JSON.generate('lat' => lat, 'lon' => lon))
  end

  def test_four_digit_postal_uses_non_us_country
    with_temp_config(default_country: 'us') do |ini, dir|
      prev_tmp = ENV['SAYTIME_TMP']
      ENV['SAYTIME_TMP'] = dir
      begin
        us_script = SaytimeWeather::WeatherScript.new(options: { config_file: ini })
        assert_equal(nil, us_script.send(:geocode_country_hint, '2000'), '4-digit with ini us has no country hint')

        au_script = SaytimeWeather::WeatherScript.new(
          options: { config_file: ini, default_country: 'au', verbose: true }
        )
        assert_equal('au', au_script.send(:geocode_country_hint, '2000'), '-d au applies to 4-digit postcodes')

        write_geocode_cache(dir, 'intl', '2000', *ALBANIA_2000)
        write_geocode_cache(dir, 'au', '2000', *SYDNEY)

        intl_coords = us_script.send(:postal_to_coordinates, '2000')
        au_coords = au_script.send(:postal_to_coordinates, '2000')

        assert_equal(ALBANIA_2000, intl_coords, '2000 without country hint uses intl cache')
        assert_equal(SYDNEY, au_coords, '2000 with -d au uses au cache')
      ensure
        if prev_tmp
          ENV['SAYTIME_TMP'] = prev_tmp
        else
          ENV.delete('SAYTIME_TMP')
        end
      end
    end
  end

  def run
    test_cli_country_overrides_ini
    test_geocode_cache_respects_country_override
    test_four_digit_postal_uses_non_us_country
  end
end

GeocodingConfigTest.new.run
puts 'geocoding_config_test: ok'
