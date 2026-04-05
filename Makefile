# Makefile for saytime-weather-rb

.PHONY: build clean install package test

build:
	@echo "No build step needed - Ruby scripts are interpreted"

clean:
	rm -rf debian/saytime-weather-rb
	rm -rf debian/.debhelper
	rm -f debian/files
	rm -f debian/substvars
	rm -f debian/*.debhelper.log
	rm -f debian/*.substvars

install:
	@echo "Use 'dpkg-buildpackage' to create Debian package"

package:
	dpkg-buildpackage -us -uc -b

test:
	@echo "Running basic syntax checks..."
	ruby -c weather.rb
	ruby -c saytime.rb
	ruby -c lib/saytime_weather.rb
	ruby -c lib/saytime_weather/version.rb
	ruby -c lib/saytime_weather/paths.rb
	ruby -c lib/saytime_weather/network.rb
	ruby -c lib/saytime_weather/endpoints.rb
	ruby -c lib/saytime_weather/http_client.rb
	ruby -c lib/saytime_weather/constants.rb
	ruby -c lib/saytime_weather/ini.rb
	ruby -c lib/saytime_weather/saytime_logging.rb
	ruby -c lib/saytime_weather/saytime_config.rb
	ruby -c lib/saytime_weather/saytime_cli.rb
	ruby -c lib/saytime_weather/saytime_playback.rb
	ruby -c lib/saytime_weather/saytime_time.rb
	ruby -c lib/saytime_weather/saytime_weather_bridge.rb
	ruby -c lib/saytime_weather/weather_helpers.rb
	ruby -c lib/saytime_weather/weather_units.rb
	ruby -c lib/saytime_weather/weather_config.rb
	ruby -c lib/saytime_weather/weather_geocoding.rb
	ruby -c lib/saytime_weather/weather_airports.rb
	ruby -c lib/saytime_weather/weather_metar.rb
	ruby -c lib/saytime_weather/weather_open_meteo.rb
	ruby -c lib/saytime_weather/weather_nws.rb
	ruby -c lib/saytime_weather/weather_sound.rb
	@echo "Syntax checks passed!"

.DEFAULT_GOAL := build

