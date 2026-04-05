# frozen_string_literal: true

module SaytimeWeather
  module SaytimeWeatherBridge
    def process_weather(location_id)
      return '' unless @options[:weather_enabled] && location_id

      temp_file_to_clean = tmp_file('temperature')
      weather_condition_file_to_clean = tmp_file('condition.ulaw')
      File.unlink(temp_file_to_clean) if File.exist?(temp_file_to_clean)
      File.unlink(weather_condition_file_to_clean) if File.exist?(weather_condition_file_to_clean)

      unless location_id =~ /^[a-zA-Z0-9\s\-_]+$/
        error("Invalid location ID format. Only alphanumeric characters, spaces, hyphens, and underscores are allowed.")
        error("  Location: #{location_id}")
        @critical_error = true
        return ''
      end

      weather_script = SaytimeWeather::Paths.weather_script_path
      weather_args = [location_id]
      weather_args = ['-d', @options[:default_country], location_id] if @options[:default_country]

      if File.executable?(weather_script)
        weather_result = system(weather_script, *weather_args)
      else
        weather_result = system('ruby', weather_script, *weather_args)
      end

      unless weather_result
        exit_code = $?.exitstatus || -1
        error("Weather script failed:")
        error("  Location: #{location_id}")
        error("  Script: #{weather_script}")
        error("  Exit code: #{exit_code}")
        error("  Hint: Check that weather.rb is installed and location ID is valid")
        @critical_error = true
        return ''
      end

      temp_file = tmp_file('temperature')
      weather_condition_file = tmp_file('condition.ulaw')
      sound_dir = @options[:custom_sound_dir] || SaytimeWeather::Paths.asterisk_sounds_en

      files = ''
      if File.exist?(temp_file)
        temp = File.read(temp_file).strip

        required_files = [
          "#{sound_dir}/silence/1.ulaw",
          "#{sound_dir}/wx/weather.ulaw",
          "#{sound_dir}/wx/conditions.ulaw",
          weather_condition_file,
          "#{sound_dir}/wx/temperature.ulaw",
          "#{sound_dir}/wx/degrees.ulaw"
        ]

        missing_count = 0
        required_files.each do |file|
          next if file == weather_condition_file

          unless File.exist?(file)
            warn("Weather sound file not found: #{file}") if @options[:verbose]
            missing_count += 1
          end
        end

        if missing_count > 0 && @options[:verbose]
          warn("#{missing_count} weather sound file(s) missing. Announcement may be incomplete.")
        end

        files = "#{sound_dir}/silence/1.ulaw " \
                "#{sound_dir}/wx/weather.ulaw " \
                "#{sound_dir}/wx/conditions.ulaw #{weather_condition_file} " \
                "#{sound_dir}/wx/temperature.ulaw "

        temp_value = temp.to_i
        if temp_value < 0
          files += add_sound_file("#{sound_dir}/digits/minus.ulaw", 0)
          temp_value = temp_value.abs
        end

        files += format_number(temp_value, sound_dir)
        files += " #{sound_dir}/wx/degrees.ulaw "
      else
        error("Temperature file not found after running weather script")
        error("  Expected: #{temp_file}")
        error("  Hint: Check that weather.rb completed successfully")
      end

      files
    end
  end
end
