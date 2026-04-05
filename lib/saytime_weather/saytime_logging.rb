# frozen_string_literal: true

module SaytimeWeather
  module SaytimeLogging
    def log_to_file(msg)
      return unless @options[:log_file] && !@options[:log_file].empty?

      line = "#{Time.now.utc.iso8601} #{msg}\n"
      File.open(@options[:log_file], 'a') { |f| f.write(line) }
    rescue => e
      $stderr.puts "WARNING: could not write log file #{@options[:log_file]}: #{e.message}"
    end

    def info(msg)
      puts msg
      log_to_file(msg)
    end

    def warn(msg)
      $stderr.puts "WARNING: #{msg}"
      log_to_file("WARNING: #{msg}")
    end

    def error(msg)
      $stderr.puts "ERROR: #{msg}"
      log_to_file("ERROR: #{msg}")
    end
  end
end
