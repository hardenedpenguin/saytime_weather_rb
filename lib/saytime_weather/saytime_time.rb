# frozen_string_literal: true

module SaytimeWeather
  module SaytimeTime
    def get_current_time(location_id)
      timezone = nil

      if ENV['TZ'] && !ENV['TZ'].empty?
        timezone = ENV['TZ'].strip
      elsif location_id
        timezone_file = tmp_file('timezone')
        if File.exist?(timezone_file)
          begin
            timezone = File.read(timezone_file).strip
          rescue => e
            # Fall through to system local time
          end
        end
      end

      if timezone && !timezone.empty?
        begin
          sanitized_tz = timezone.gsub(/[^a-zA-Z0-9\/_\-+: ]/, '')
          if sanitized_tz.empty?
            # invalid
          elsif sanitized_tz != timezone
            # invalid
          else
            time_parts = nil
            IO.popen({ 'TZ' => sanitized_tz }, ['date', '+%H %M %S']) do |io|
              time_parts = io.read.strip
            end

            if $?.success? && time_parts && !time_parts.empty?
              parts = time_parts.split.map(&:to_i)
              if parts.length >= 2
                hour, minute, second = parts[0], parts[1], (parts[2] || 0)
                now = Time.now
                time = Time.new(now.year, now.month, now.day, hour, minute, second)
                return time
              end
            end
          end
        rescue => e
          # Fall through to system local time
        end
      end

      Time.now
    end

    def process_time(now, use_24hour)
      files = []
      sound_dir = @options[:custom_sound_dir] || SaytimeWeather::Paths.asterisk_sounds_en
      @missing_files = 0

      if @options[:greeting_enabled]
        hour = now.hour
        greeting = if hour < 12
                     'morning'
                   elsif hour < 18
                     'afternoon'
                   else
                     'evening'
                   end
        files << add_sound_file("#{sound_dir}/rpt/good#{greeting}.ulaw", @missing_files)
      end

      files << add_sound_file("#{sound_dir}/rpt/thetimeis.ulaw", @missing_files)

      hour = now.hour
      minute = now.min

      if use_24hour
        files << add_sound_file("#{sound_dir}/digits/0.ulaw", @missing_files) if hour < 10
        files << format_number(hour, sound_dir)

        if minute == 0
          files << add_sound_file("#{sound_dir}/digits/hundred.ulaw", @missing_files)
          files << add_sound_file("#{sound_dir}/hours.ulaw", @missing_files)
        else
          files << add_sound_file("#{sound_dir}/digits/0.ulaw", @missing_files) if minute < 10
          files << format_number(minute, sound_dir)
          files << add_sound_file("#{sound_dir}/hours.ulaw", @missing_files)
        end
      else
        display_hour = (hour == 0 || hour == 12) ? 12 : (hour > 12 ? hour - 12 : hour)
        files << add_sound_file("#{sound_dir}/digits/#{display_hour}.ulaw", @missing_files)

        if minute != 0
          if minute < 10
            o_file = "#{sound_dir}/letters/o.ulaw"
            files << add_sound_file(File.exist?(o_file) ? o_file : "#{sound_dir}/digits/0.ulaw", @missing_files)
          end
          files << format_number(minute, sound_dir)
        end
        am_pm = hour < 12 ? 'a-m' : 'p-m'
        files << add_sound_file("#{sound_dir}/digits/#{am_pm}.ulaw", 0)
      end

      warn("#{@missing_files} sound file(s) missing. Run with -v for details.") if @missing_files > 0 && !@options[:verbose]

      files.join(' ')
    end

    def format_number(num, sound_dir)
      files = ''
      abs_num = num.abs

      return "#{sound_dir}/digits/0.ulaw " if abs_num == 0

      if abs_num >= 100
        hundreds = abs_num / 100
        files += "#{sound_dir}/digits/#{hundreds}.ulaw "
        files += "#{sound_dir}/digits/hundred.ulaw "
        abs_num %= 100
        return files if abs_num == 0
      end

      if abs_num < 20
        files += "#{sound_dir}/digits/#{abs_num}.ulaw "
      else
        tens = (abs_num / 10) * 10
        ones = abs_num % 10
        files += "#{sound_dir}/digits/#{tens}.ulaw "
        files += "#{sound_dir}/digits/#{ones}.ulaw " if ones > 0
      end

      files
    end

    def add_sound_file(file, missing_count)
      if File.exist?(file)
        "#{file} "
      else
        @missing_files = (@missing_files || 0) + 1
        if @options[:verbose]
          warn("Sound file not found: #{file}")
          warn("  Expected location: #{file}")
          warn("  Check that sound files are installed correctly")
        end
        "#{file} "
      end
    end
  end
end
