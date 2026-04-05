# frozen_string_literal: true

module SaytimeWeather
  module Endpoints
    module_function

    NOMINATIM_SEARCH = 'https://nominatim.openstreetmap.org/search'
    OPEN_METEO_FORECAST = 'https://api.open-meteo.com/v1/forecast'
    NWS_POINTS = 'https://api.weather.gov/points'
    AVIATION_METAR = 'https://aviationweather.gov/api/data/metar'
    NOAA_METAR_STATION = 'https://tgftp.nws.noaa.gov/data/observations/metar/stations'

    DEFAULT_HTTP_UA = 'Mozilla/5.0 (compatible; WeatherBot/1.0)'
    NWS_API_UA = 'WeatherBot/1.0 (saytime-weather@github.com)'

    def nominatim_postal_url(postal, country: nil)
      q = URI.encode_www_form_component(postal)
      if country
        "#{NOMINATIM_SEARCH}?postalcode=#{q}&country=#{URI.encode_www_form_component(country)}&format=json&limit=1"
      else
        "#{NOMINATIM_SEARCH}?postalcode=#{q}&format=json&limit=1"
      end
    end

    def open_meteo_url(lat, lon, current_params)
      "#{OPEN_METEO_FORECAST}?latitude=#{lat}&longitude=#{lon}&current=#{current_params}&" \
        'temperature_unit=fahrenheit&wind_speed_unit=ms&precipitation_unit=mm&timezone=auto'
    end

    def nws_points_url(lat, lon)
      "#{NWS_POINTS}/#{lat},#{lon}"
    end

    def nws_station_observation_url(station_id)
      "https://api.weather.gov/stations/#{URI.encode_www_form_component(station_id)}/observations/latest"
    end

    def aviation_metar_url(icao)
      "#{AVIATION_METAR}?ids=#{URI.encode_www_form_component(icao)}&format=raw&hours=0&taf=false"
    end

    def noaa_metar_file_url(icao)
      "#{NOAA_METAR_STATION}/#{URI.encode_www_form_component(icao)}.TXT"
    end
  end
end
