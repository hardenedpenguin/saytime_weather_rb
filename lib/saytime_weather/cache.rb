# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative 'run_context'

module SaytimeWeather
  module Cache
    module_function

    def read_json(path, max_age_seconds)
      return nil unless path && File.exist?(path)
      return nil if max_age_seconds.to_i > 0 && (Time.now - File.mtime(path)) > max_age_seconds.to_i

      JSON.parse(File.read(path))
    rescue JSON::ParserError, Errno::ENOENT
      nil
    end

    def write_json(path, data)
      dir = File.dirname(path)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      RunContext.write_file_atomic(path, JSON.generate(data))
      true
    rescue StandardError
      false
    end
  end
end
