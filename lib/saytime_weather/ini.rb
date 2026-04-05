# frozen_string_literal: true

module SaytimeWeather
  module Ini
    module_function

    def parse_file(file_path)
      result = {}
      current_section = nil
      File.readlines(file_path).each do |line|
        line = line.strip
        next if line.empty? || line.start_with?('#', ';')
        if line =~ /^\[(.+)\]$/
          result[current_section = $1] ||= {}
        elsif line =~ /^([^=]+)=(.*)$/ && current_section
          result[current_section][$1.strip] = $2.strip.gsub(/^["']|["']$/, '')
        end
      end
      result
    end
  end
end
