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

      unless invoke_weather_script(location_id)
        error("Weather script failed:")
        error("  Location: #{location_id}")
        error("  Hint: Check that weather.rb completed successfully and location ID is valid")
        @critical_error = true
        return ''
      end

      build_weather_sound_files
    end

    private

    def invoke_weather_script(location_id)
      if @options[:weather_subprocess]
        run_weather_subprocess(location_id)
      else
        SaytimeWeather.run_weather(location_id, weather_invoke_options)
      end
    end

    def run_weather_subprocess(location_id)
      weather_script = Paths.weather_script_path
      args = weather_subprocess_argv(location_id)

      if File.executable?(weather_script)
        system(weather_script, *args)
      else
        system('ruby', weather_script, *args)
      end
    end

    def weather_subprocess_argv(location_id)
      args = []
      args << '-v' if @options[:verbose]
      args += ['-c', @options[:config_file]] if @options[:config_file]
      args += ['-d', @options[:default_country]] if @options[:default_country]
      args += ['-t', @config['Temperature_mode']] if @config['Temperature_mode']
      args << '--no-condition' if @config['process_condition'] == 'NO'
      args << location_id
      args
    end

    def weather_invoke_options
      opts = { verbose: @options[:verbose] }
      opts[:config_file] = @options[:config_file] if @options[:config_file]
      opts[:default_country] = @options[:default_country] if @options[:default_country]
      opts[:temperature_mode] = @config['Temperature_mode'] if @config['Temperature_mode']
      opts[:no_condition] = true if @config['process_condition'] == 'NO'
      opts
    end

    def build_weather_sound_files
      temp_file = tmp_file('temperature')
      weather_condition_file = tmp_file('condition.ulaw')
      sound_dir = @options[:custom_sound_dir] || Paths.asterisk_sounds_en

      files = ''
      unless File.exist?(temp_file)
        error("Temperature file not found after running weather script")
        error("  Expected: #{temp_file}")
        error("  Hint: Check that weather.rb completed successfully")
        return files
      end

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
        files += add_sound_file("#{sound_dir}/digits/minus.ulaw")
        temp_value = temp_value.abs
      end

      files += format_number(temp_value, sound_dir)
      files + " #{sound_dir}/wx/degrees.ulaw "
    end
  end
end
