# frozen_string_literal: true

require 'etc'

module SaytimeWeather
  # Per-invocation scratch file namespace (avoids /tmp races between concurrent runs).
  module RunContext
    LEGACY_SCRATCH_NAMES = %w[
      temperature
      condition.ulaw
      timezone
      current-time.ulaw
    ].freeze

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

    def cleanup!(except: [])
      skip = except.map { |p| File.expand_path(p.to_s) }
      scratch_files.each do |path|
        next unless path
        next if skip.include?(File.expand_path(path))

        File.unlink(path) if File.exist?(path)
      rescue
        nil
      end
      @scratch_files = []
      @run_id = nil
    end

    def clear_legacy_timezone!
      clear_legacy_scratch!
    end

    # Remove fixed /tmp names left by older releases or root cron (blocks asterisk DTMF runs).
    def clear_legacy_scratch!
      LEGACY_SCRATCH_NAMES.each do |name|
        path = File.join(Paths.tmp_dir, name)
        File.unlink(path) if File.exist?(path)
      rescue
        nil
      end
    end

    # Stable path for -s 1 / -s 2 saves; not tracked for automatic cleanup.
    def persistent_scratch_path(name)
      File.join(Paths.tmp_dir, name)
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

    def apply_runtime_owner(path)
      return unless path && File.exist?(path)

      info = runtime_file_owner
      return unless info

      File.chown(info[:uid], info[:gid], path)
    rescue
      nil
    end

    def runtime_file_owner
      name = ENV.fetch('SAYTIME_FILE_OWNER', 'asterisk').to_s.strip
      return nil if name.empty?

      pw = Etc.getpwnam(name)
      { uid: pw.uid, gid: pw.gid }
    rescue
      nil
    end
  end
end
