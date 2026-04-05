# frozen_string_literal: true

module SaytimeWeather
  module SaytimePlayback
    def tmp_file(name)
      File.join(SaytimeWeather::Paths.tmp_dir, name)
    end

    def is_safe_path(file)
      return false if file.include?('..')

      SaytimeWeather::Paths.sound_path_prefixes(@options[:custom_sound_dir]).any? { |p| file.start_with?(p) }
    end

    def combine_sound_files(time_files, weather_files)
      if @options[:silent] == 0 || @options[:silent] == 1
        "#{time_files} #{weather_files}"
      elsif @options[:silent] == 2
        weather_files
      else
        ''
      end
    end

    def create_output_file(input_files, output_file)
      buf = SaytimeWeather::HTTP_BUFFER_SIZE
      File.open(output_file, 'wb') do |out|
        files = input_files.split(/\s+/).select { |f| f =~ /\.ulaw$/ }
        files_processed = 0

        files.each do |file|
          next unless file

          unless is_safe_path(file)
            warn("Skipping potentially unsafe file path: #{file}")
            next
          end

          if File.exist?(file)
            File.open(file, 'rb') do |in_file|
              while chunk = in_file.read(buf)
                out.write(chunk)
              end
            end
            files_processed += 1
          else
            warn("Sound file not found: #{file}")
            warn("  Expected location: #{file}")
            warn("  Check that sound files are installed in the sound directory")
          end
        end

        raise 'No valid sound files were processed' if files_processed == 0
      end
    rescue => e
      error("Failed to create output file:")
      error("  Output: #{output_file}")
      error("  Error: #{e.message}")
      error("  Hint: Check file permissions and disk space")
      @critical_error = true
    end

    def play_announcement(node, asterisk_file)
      asterisk_file = asterisk_file.sub(/\.ulaw$/, '')

      unless node =~ /^\d+$/
        error("Invalid node number format: #{node}")
        @critical_error = true
        return
      end

      unless @options[:play_method] =~ /^(localplay|playback)$/
        error("Invalid play method: #{@options[:play_method]}")
        @critical_error = true
        return
      end

      asterisk_file = asterisk_file.gsub(/[^a-zA-Z0-9\/\-_\.]/, '')

      if @options[:test_mode]
        info("Test mode - would execute: rpt #{@options[:play_method]} #{node} #{asterisk_file}")
        return
      end

      asterisk_cmd = "rpt #{@options[:play_method]} #{node} #{asterisk_file}"

      result = system(SaytimeWeather::Paths.asterisk_bin, '-rx', asterisk_cmd)
      unless result
        exit_code = $?.exitstatus || -1
        error("Failed to play announcement:")
        error("  Method: #{@options[:play_method]}")
        error("  Node: #{node}")
        error("  File: #{asterisk_file}")
        error("  Exit code: #{exit_code}")
        error("  Hint: Verify Asterisk is running and node number is correct")
        @critical_error = true
      end
      sleep SaytimeWeather::SAYTIME_PLAY_DELAY
    end

    def cleanup_files(file_to_delete, weather_enabled, silent)
      if file_to_delete && silent == 0
        File.unlink(file_to_delete) if File.exist?(file_to_delete)
      end

      if weather_enabled && [0, 1, 2].include?(silent)
        weather_files = [
          tmp_file('temperature'),
          tmp_file('condition.ulaw'),
          tmp_file('timezone')
        ]

        weather_files.each do |file|
          File.unlink(file) if File.exist?(file)
        end
      end
    end
  end
end
