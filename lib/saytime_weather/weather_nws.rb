# frozen_string_literal: true

module SaytimeWeather
  module WeatherNws
    def fetch_weather_nws(lat, lon)
      return nil if lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0

      if lat < 18.0 || lat > 72.0 || lon < -180.0 || lon > -50.0
        return nil
      end

      lat_rounded = lat.round(4)
      lon_rounded = lon.round(4)
      points_url = SaytimeWeather::Endpoints.nws_points_url(lat_rounded, lon_rounded)
      nws_ua = SaytimeWeather::Endpoints::NWS_API_UA
      response = @http.get(points_url, SaytimeWeather::Network.timeout_long, nws_ua)
      return nil unless response

      points_data = safe_decode_json(response)
      return nil unless points_data && points_data['properties']

      timezone = points_data['properties']['timeZone'] || ''
      observation_stations_url = points_data['properties']['observationStations']

      temp = nil
      condition = nil
      precipitation = nil
      wind_speed = nil
      wind_direction = nil
      wind_gusts = nil
      pressure = nil
      humidity = nil

      if observation_stations_url
        response = @http.get(observation_stations_url, SaytimeWeather::Network.timeout_long, nws_ua)
        if response
          stations_data = safe_decode_json(response)
          if stations_data && stations_data['features'] && stations_data['features'].any?
            stations_data['features'].each do |station|
              station_id = station['properties']['stationIdentifier']
              next unless station_id

              obs_url = SaytimeWeather::Endpoints.nws_station_observation_url(station_id)
              response = @http.get(obs_url, SaytimeWeather::Network.timeout_long, nws_ua)
              next unless response

              obs_data = safe_decode_json(response)
              next unless obs_data && obs_data['properties']
              props = obs_data['properties']

              temp_c = props['temperature'] && props['temperature']['value']
              if temp_c && temp_c.is_a?(Numeric)
                temp = (temp_c * 9.0 / 5.0) + 32.0
              end

              condition_text = props['textDescription'] || ''
              if condition_text && !condition_text.empty?
                condition = parse_nws_condition(condition_text)
              end

              unless condition
                icon = props['icon'] || ''
                if icon.include?('skc') || icon.include?('clear')
                  condition = 'Clear'
                elsif icon.include?('few')
                  condition = 'Clear'
                elsif icon.include?('sct')
                  condition = 'Partly Cloudy'
                elsif icon.include?('bkn') || icon.include?('ovc')
                  condition = 'Cloudy'
                end
              end

              if @config['show_precipitation'] == 'YES'
                precip_mm = props['precipitationLastHour'] && props['precipitationLastHour']['value']
                precipitation = precip_mm if precip_mm && precip_mm.is_a?(Numeric)
              end

              if @config['show_wind'] == 'YES'
                ws_obj = props['windSpeed']
                if ws_obj && ws_obj['value'] && ws_obj['value'].is_a?(Numeric)
                  ws_value = ws_obj['value']
                  unit_code = (ws_obj['unitCode'] || '').downcase

                  if unit_code.include?('mi_h') || unit_code.include?('mph') || unit_code.include?('mile')
                    wind_speed = ws_value / 2.23694
                  elsif unit_code.include?('km_h') || unit_code.include?('kmh') || unit_code.include?('kilometer')
                    wind_speed = ws_value / 3.6
                  elsif unit_code.include?('kt') || unit_code.include?('knot')
                    wind_speed = ws_value * 0.514444
                  elsif unit_code.include?('m_s') || unit_code.include?('meter') || unit_code.empty?
                    wind_speed = ws_value
                  else
                    if @options[:verbose] && !unit_code.empty?
                      warn("Unknown wind speed unitCode: #{ws_obj['unitCode']}, assuming m/s")
                    end
                    wind_speed = ws_value
                  end
                end

                wd = props['windDirection'] && props['windDirection']['value']
                wind_direction = wd if wd && wd.is_a?(Numeric)

                wg_obj = props['windGust']
                if wg_obj && wg_obj['value'] && wg_obj['value'].is_a?(Numeric)
                  wg_value = wg_obj['value']
                  wg_unit_code = wg_obj['unitCode'] || ''

                  if wg_unit_code.include?('mi_h-1') || wg_unit_code.include?('mph')
                    wind_gusts = wg_value / 2.23694
                  elsif wg_unit_code.include?('km_h-1') || wg_unit_code.include?('kmh')
                    wind_gusts = wg_value / 3.6
                  elsif wg_unit_code.include?('kt') || wg_unit_code.include?('knot')
                    wind_gusts = wg_value * 0.514444
                  elsif wg_unit_code.include?('m_s-1') || wg_unit_code.include?('ms')
                    wind_gusts = wg_value
                  else
                    wind_gusts = wg_value
                  end
                end
              end

              if @config['show_pressure'] == 'YES'
                press_pa = props['seaLevelPressure'] && props['seaLevelPressure']['value']
                if press_pa && press_pa.is_a?(Numeric)
                  pressure = press_pa / 100.0
                end
              end

              if @config['show_humidity'] == 'YES'
                rh = props['relativeHumidity'] && props['relativeHumidity']['value']
                humidity = rh if rh && rh.is_a?(Numeric)
              end

              break if temp && condition
            end
          end
        end
      end

      unless temp && condition
        forecast_url = points_data['properties']['forecast']
        if forecast_url
          response = @http.get(forecast_url, SaytimeWeather::Network.timeout_long, nws_ua)
          if response
            forecast_data = safe_decode_json(response)
            if forecast_data && forecast_data['properties']
              periods = forecast_data['properties']['periods']
              if periods && periods.any?
                current = periods[0]
                if current
                  forecast_temp = current['temperature']
                  if !temp && forecast_temp && forecast_temp.is_a?(Numeric)
                    temp = forecast_temp
                  end
                  condition_text = current['shortForecast'] || current['detailedForecast'] || ''
                  if condition_text && !condition_text.empty? && !condition
                    condition = parse_nws_condition(condition_text)
                  end
                end
              end
            end
          end
        end
      end

      return nil unless temp && condition

      write_timezone_file(timezone)

      {
        temp: temp,
        condition: condition,
        timezone: timezone,
        precipitation: precipitation,
        wind_speed: wind_speed,
        wind_direction: wind_direction,
        wind_gusts: wind_gusts,
        pressure: pressure,
        humidity: humidity
      }
    end

    def parse_nws_condition(text)
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
      return 'Cloudy' if text =~ /\bcloudy\b/
      return 'Partly Cloudy' if text =~ /partly.*cloud|partly.*sun|mostly.*cloud/
      return 'Mostly Sunny' if text =~ /mostly.*sun|mostly.*clear/
      return 'Sunny' if text =~ /\bsunny\b|clear.*sun|sun.*clear/
      return 'Clear' if text =~ /\bclear\b/
      'Clear'
    end
  end
end
