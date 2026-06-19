# frozen_string_literal: true

module SaytimeWeather
  module SaytimeTime
    def get_current_time(location_id)
      timezone = read_location_timezone(location_id)
      timezone = ENV['TZ'].strip if timezone.to_s.empty? && ENV['TZ'] && !ENV['TZ'].empty?

      if timezone && !timezone.empty?
        sanitized_tz = timezone.gsub(/[^a-zA-Z0-9\/_\-+: ]/, '')
        unless sanitized_tz.empty? || sanitized_tz != timezone
          t = time_in_timezone(sanitized_tz)
          return t if t
        end
      end

      Time.now
    end

    def read_location_timezone(location_id)
      return nil unless location_id
      return nil unless @options[:weather_enabled]

      timezone_file = tmp_file('timezone')
      return nil unless File.exist?(timezone_file)

      File.read(timezone_file).strip
    rescue
      nil
    end

    def time_in_timezone(tz)
      time_parts = nil
      IO.popen({ 'TZ' => tz }, ['date', '+%Y %m %d %H %M %S']) do |io|
        time_parts = io.read.strip
      end

      return nil unless $?.success? && time_parts && !time_parts.empty?

      parts = time_parts.split.map(&:to_i)
      return nil unless parts.length >= 6

      Time.new(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5])
    rescue
      nil
    end

    # 24-hour clock (0–23) from the resolved announcement time. Greeting and a-m/p-m must
    # both use this value — never the 12-hour display digit (e.g. 2 PM → hour24 14, not 2).
    def hour24(now)
      now.hour
    end

    def greeting_for_hour24(hour24)
      if hour24 < 12
        'morning'
      elsif hour24 < 18
        'afternoon'
      else
        'evening'
      end
    end

    def twelve_hour_display(hour24)
      (hour24 == 0 || hour24 == 12) ? 12 : (hour24 > 12 ? hour24 - 12 : hour24)
    end

    def meridian_sound(hour24)
      hour24 < 12 ? 'a-m' : 'p-m'
    end

    # a-m/p-m: prefer stock Asterisk digits/ (package en/ copies were wrong on some nodes).
    def meridian_sound_path(sound_dir, meridian)
      sound_path(sound_dir, "#{meridian}.ulaw", prefer_digits: true)
    end

    def process_time(now, use_24hour)
      files = []
      sound_dir = @options[:custom_sound_dir] || Paths.asterisk_sounds_en
      @missing_files = 0

      clock = hour24(now)
      minute = now.min

      if @options[:verbose]
        info("Announcing time #{format('%02d:%02d', clock, minute)} (#{use_24hour ? '24-hour' : "12-hour, #{meridian_sound(clock)}"})")
      end

      if @options[:greeting_enabled]
        files << add_sound_file("#{sound_dir}/rpt/good#{greeting_for_hour24(clock)}.ulaw")
      end

      files << add_sound_file("#{sound_dir}/rpt/thetimeis.ulaw")

      if use_24hour
        files << add_sound_file("#{sound_dir}/digits/0.ulaw") if clock < 10
        files << format_number(clock, sound_dir)

        if minute == 0
          files << add_sound_file(sound_path(sound_dir, 'hundred.ulaw'))
          files << add_sound_file(sound_path(sound_dir, 'hours.ulaw'))
        else
          files << add_sound_file("#{sound_dir}/digits/0.ulaw") if minute < 10
          files << format_number(minute, sound_dir)
          files << add_sound_file(sound_path(sound_dir, 'hours.ulaw'))
        end
      else
        display_hour = twelve_hour_display(clock)
        files << add_sound_file("#{sound_dir}/digits/#{display_hour}.ulaw")

        if minute != 0
          # 2:06 -> "two oh six"; 2:10 -> "two ten" (oh only for minutes 1-9)
          if minute < 10
            o_file = sound_path(sound_dir, 'letters/o.ulaw')
            files << add_sound_file(indexed_file_exists?(o_file) ? o_file : "#{sound_dir}/digits/0.ulaw")
          end
          files << format_number(minute, sound_dir)
        end
        files << add_sound_file(meridian_sound_path(sound_dir, meridian_sound(clock)))
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
        files += "#{sound_path(sound_dir, 'hundred.ulaw')} "
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

    # prefer_digits: true for a-m/p-m (stock under digits/). false for hours/hundred (usually en/).
    def sound_path(sound_dir, name, prefer_digits: false)
      candidates = if prefer_digits
                       [File.join(sound_dir, 'digits', name), File.join(sound_dir, name)]
                     else
                       [File.join(sound_dir, name), File.join(sound_dir, 'digits', name)]
                     end
      candidates.find { |p| indexed_file_exists?(p) } || candidates.first
    end

    def indexed_file_exists?(path)
      idx = sound_index_for(@options[:custom_sound_dir] || Paths.asterisk_sounds_en)
      idx['abs_set'][path] || File.exist?(path)
    end

    def add_sound_file(file)
      unless indexed_file_exists?(file)
        @missing_files = (@missing_files || 0) + 1
        if @options[:verbose]
          warn("Sound file not found: #{file}")
          warn("  Expected location: #{file}")
          warn("  Check that sound files are installed correctly")
        end
      end
      "#{file} "
    end
  end
end
