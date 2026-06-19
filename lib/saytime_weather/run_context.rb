# frozen_string_literal: true

module SaytimeWeather
  # Per-invocation scratch file namespace (avoids /tmp races between concurrent runs).
  module RunContext
    module_function

    def begin_run!(id = nil)
      @run_id = id || "#{Process.pid}-#{Time.now.to_i}"
      @scratch_files = []
      @run_id
    end

    def run_id
      @run_id ||= begin_run!
    end

    def active?
      !@run_id.nil?
    end

    def ensure_run!
      begin_run! unless active?
      @run_id
    end

    def scratch_files
      @scratch_files ||= []
    end

    def track(path)
      scratch_files << path
      path
    end

    def cleanup!
      scratch_files.each do |path|
        File.unlink(path) if path && File.exist?(path)
      rescue
        nil
      end
      @scratch_files = []
      @run_id = nil
    end

    def clear_legacy_timezone!
      legacy = File.join(Paths.tmp_dir, 'timezone')
      File.unlink(legacy) if File.exist?(legacy)
    rescue
      nil
    end

    def scoped_tmp_path(name)
      run_id = self.run_id
      if name.end_with?('.ulaw')
        base = name[0..-6]
        track(File.join(Paths.tmp_dir, "#{base}.#{run_id}.ulaw"))
      else
        track(File.join(Paths.tmp_dir, "#{name}.#{run_id}"))
      end
    end
  end
end
