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

    def process_time(now, use_24hour)
      files = []
      sound_dir = @options[:custom_sound_dir] || Paths.asterisk_sounds_en
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
        files << add_sound_file("#{sound_dir}/rpt/good#{greeting}.ulaw")
      end

      files << add_sound_file("#{sound_dir}/rpt/thetimeis.ulaw")

      hour = now.hour
      minute = now.min

      if use_24hour
        files << add_sound_file("#{sound_dir}/digits/0.ulaw") if hour < 10
        files << format_number(hour, sound_dir)

        if minute == 0
          files << add_sound_file(sound_path(sound_dir, 'hundred.ulaw'))
          files << add_sound_file(sound_path(sound_dir, 'hours.ulaw'))
        else
          files << add_sound_file("#{sound_dir}/digits/0.ulaw") if minute < 10
          files << format_number(minute, sound_dir)
          files << add_sound_file(sound_path(sound_dir, 'hours.ulaw'))
        end
      else
        display_hour = (hour == 0 || hour == 12) ? 12 : (hour > 12 ? hour - 12 : hour)
        files << add_sound_file("#{sound_dir}/digits/#{display_hour}.ulaw")

        if minute != 0
          o_file = sound_path(sound_dir, 'letters/o.ulaw')
          files << add_sound_file(indexed_file_exists?(o_file) ? o_file : "#{sound_dir}/digits/0.ulaw")
          files << format_number(minute, sound_dir)
        end
        am_pm = hour < 12 ? 'a-m' : 'p-m'
        files << add_sound_file(sound_path(sound_dir, "#{am_pm}.ulaw"))
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

    def sound_path(sound_dir, name)
      candidates = [
        File.join(sound_dir, name),
        File.join(sound_dir, 'digits', name)
      ]
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
