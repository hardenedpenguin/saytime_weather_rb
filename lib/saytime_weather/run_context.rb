# frozen_string_literal: true

require 'etc'
require 'fileutils'
require 'tmpdir'
require_relative 'paths'

module SaytimeWeather
  # Per-invocation scratch directory (avoids /tmp races and symlink attacks between runs).
  #
  # Each run gets a freshly created, uniquely named directory under Paths.tmp_dir.
  # Only the creating user can write to it, so scratch file names inside it cannot be
  # pre-planted as symlinks by other local users. It is world-readable (0755) so that
  # Asterisk can read the combined announcement even when cron runs saytime.rb as root.
  #
  # A parent process can hand its run directory to a child (weather.rb subprocess) via
  # the SAYTIME_RUN_DIR environment variable; the child then reuses it and leaves
  # cleanup to the parent.
  module RunContext
    RUN_DIR_ENV = 'SAYTIME_RUN_DIR'

    LEGACY_SCRATCH_NAMES = %w[
      temperature
      condition.ulaw
      timezone
      current-time.ulaw
    ].freeze

    module_function

    def begin_run!(id = nil)
      cleanup_dir_only!
      @run_id = id || "#{Process.pid}-#{Time.now.to_i}"
      @scratch_files = []
      @run_dir = nil
      @owns_run_dir = true
      @run_id
    end

    def run_id
      ensure_run!
      @run_id
    end

    def active?
      !@run_id.nil?
    end

    def ensure_run!
      return @run_id if active?

      inherited = inherited_run_dir
      if inherited
        @run_id = File.basename(inherited)
        @scratch_files = []
        @run_dir = inherited
        @owns_run_dir = false
        return @run_id
      end

      begin_run!
    end

    # Directory for this run's scratch files (created on first use).
    def run_dir
      ensure_run!
      @run_dir ||= create_run_dir
    end

    # Environment to pass to a child process so it shares this run's scratch directory.
    def child_env
      { RUN_DIR_ENV => run_dir }
    end

    def scratch_files
      @scratch_files ||= []
    end

    def track(path)
      scratch_files << path
      path
    end

    def cleanup!(except: [])
      # A child sharing the parent's run directory must leave its files for the parent.
      if active? && @owns_run_dir == false
        @scratch_files = []
        @run_dir = nil
        @run_id = nil
        return
      end

      skip = except.map { |p| File.expand_path(p.to_s) }
      scratch_files.each do |path|
        next unless path
        next if skip.include?(File.expand_path(path))

        File.unlink(path) if File.exist?(path)
      rescue StandardError
        nil
      end
      cleanup_dir_only!
      @scratch_files = []
      @run_id = nil
    end

    def clear_legacy_timezone!
      clear_legacy_scratch!
    end

    # Remove fixed /tmp names left by older releases or root cron (blocks asterisk DTMF runs).
    # Only regular files and symlinks are removed; File.unlink never follows symlinks.
    def clear_legacy_scratch!
      LEGACY_SCRATCH_NAMES.each do |name|
        path = File.join(Paths.tmp_dir, name)
        File.unlink(path) if File.symlink?(path) || File.file?(path)
      rescue StandardError
        nil
      end
    end

    # Stable path for -s 1 / -s 2 saves; not tracked for automatic cleanup.
    # Write it with write_file_atomic so a planted symlink is replaced, never followed.
    def persistent_scratch_path(name)
      File.join(Paths.tmp_dir, name)
    end

    def scoped_tmp_path(name)
      track(File.join(run_dir, File.basename(name.to_s)))
    end

    # Write data to a unique temp file beside +path+, then rename it into place.
    # rename(2) replaces a symlink at +path+ instead of writing through it.
    def write_file_atomic(path, data = nil, mode: 0o644)
      dir = File.dirname(path)
      tmp = File.join(dir, ".#{File.basename(path)}.#{Process.pid}.#{rand(1 << 32).to_s(16)}.part")
      File.open(tmp, File::WRONLY | File::CREAT | File::EXCL | File::BINARY, mode) do |f|
        if block_given?
          yield f
        else
          f.write(data.to_s)
        end
      end
      File.rename(tmp, path)
      path
    rescue StandardError
      File.unlink(tmp) if tmp && File.exist?(tmp)
      raise
    end

    def apply_runtime_owner(path)
      return unless path && File.exist?(path)

      info = runtime_file_owner
      return unless info

      File.chown(info[:uid], info[:gid], path)
    rescue StandardError
      nil
    end

    def runtime_file_owner
      name = ENV.fetch('SAYTIME_FILE_OWNER', 'asterisk').to_s.strip
      return nil if name.empty?

      pw = Etc.getpwnam(name)
      { uid: pw.uid, gid: pw.gid }
    rescue StandardError
      nil
    end

    def create_run_dir
      base = Paths.tmp_dir
      FileUtils.mkdir_p(base) unless Dir.exist?(base)
      dir = Dir.mktmpdir("saytime-run-#{@run_id}-", base)
      File.chmod(0o755, dir)
      dir
    end

    def inherited_run_dir
      dir = ENV[RUN_DIR_ENV].to_s
      return nil if dir.empty?
      return nil unless File.directory?(dir) && !File.symlink?(dir)
      return nil unless File.stat(dir).owned?

      dir
    rescue StandardError
      nil
    end

    def cleanup_dir_only!
      if @run_dir && @owns_run_dir
        FileUtils.rm_rf(@run_dir, secure: true)
      end
      @run_dir = nil
    rescue StandardError
      @run_dir = nil
    end
  end
end
