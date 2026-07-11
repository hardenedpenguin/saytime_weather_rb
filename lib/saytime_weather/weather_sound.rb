# frozen_string_literal: true

module SaytimeWeather
  module WeatherSound
    def cleanup_old_files
      [temp_path('temperature'), temp_path('condition.ulaw'), temp_path('timezone')].each do |file|
        if File.exist?(file)
          File.unlink(file) rescue nil
        end
      end
    end

    def process_weather_condition(condition_text)
      return unless Dir.exist?(weather_sound_dir)

      condition_lower = condition_text.downcase
      condition_files = []

      important_words = %w[snow rain thunderstorm hail sleet fog drizzle showers cloudy overcast sunny clear]
      modifiers = %w[light heavy freezing mostly partly]

      [condition_lower, condition_lower.gsub(/\s+/, '-'), condition_lower.gsub(/\s+/, '_'), condition_lower.gsub(/\s+/, '')].each do |variant|
        file = "#{weather_sound_dir}/#{variant}.ulaw"
        if File.exist?(file)
          condition_files << file
          break
        end
      end

      if condition_files.empty?
        words = condition_lower.split(/\s+/).reject(&:empty?)
        words.each do |word|
          file = "#{weather_sound_dir}/#{word}.ulaw"
          condition_files << file if File.exist?(file)
        end
      end

      if condition_files.empty?
        words = condition_lower.split(/\s+/).reject(&:empty?)
        sorted_words = words.sort_by { |w| important_words.include?(w) ? 0 : (modifiers.include?(w) ? 1 : 2) }
        wx_names = wx_basenames_for(weather_sound_dir)
        wx_names.each do |filename|
          sorted_words.each do |word|
            if filename == word || (filename.include?(word) && word.length >= 4)
              condition_files << "#{weather_sound_dir}/#{filename}.ulaw"
              break
            end
          end
          break if condition_files.any?
        end
      end

      if condition_files.any?
        File.open(temp_path('condition.ulaw'), 'wb') do |out|
          condition_files.each do |file|
            next unless File.exist?(file)

            File.open(file, 'rb') do |in_file|
              IO.copy_stream(in_file, out)
            end
          end
        end
      else
        warn("No weather condition sound files found for: #{condition_text}", true)
        warn("  Expected sound directory: #{weather_sound_dir}", true)
        warn("  Hint: Install weather sound files or disable condition announcements", true)
      end
    end

    def wx_basenames_for(wx_dir)
      @wx_basenames_cache ||= {}
      @wx_basenames_cache[wx_dir] ||= Dir.glob("#{wx_dir}/*.ulaw").map { |f| File.basename(f, '.ulaw').downcase }
    end
  end
end
