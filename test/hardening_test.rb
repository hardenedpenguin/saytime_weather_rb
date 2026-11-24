#!/usr/bin/env ruby
# frozen_string_literal: true

# Regression tests for scratch/cache file safety, HTTP client behavior, GPS timeouts,
# time zone lookup, and weather.rb display-only argument handling.

require 'fileutils'
require 'socket'
require 'tmpdir'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'saytime_weather'

def assert!(cond, msg)
  raise msg unless cond
end

def with_env(vars)
  prev = vars.keys.map { |k| [k, ENV[k]] }.to_h
  vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  yield
ensure
  prev.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
end

def monotonic
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

Dir.mktmpdir do |tmp|
  with_env('SAYTIME_TMP' => tmp, 'SAYTIME_CACHE_DIR' => nil, 'SAYTIME_RUN_DIR' => nil) do
    rc = SaytimeWeather::RunContext

    # --- write_file_atomic replaces a planted symlink instead of writing through it ---
    victim = File.join(tmp, 'victim')
    File.write(victim, 'original')
    link = File.join(tmp, 'current-time.ulaw')
    File.symlink(victim, link)
    rc.write_file_atomic(link, 'audio')
    assert!(File.read(victim) == 'original', 'atomic write must not follow symlink')
    assert!(!File.symlink?(link) && File.read(link) == 'audio', 'atomic write must replace symlink')
    assert!(Dir.glob(File.join(tmp, '.*.part')).empty?, 'no temp files left behind')

    # Block form (used for the combined announcement).
    rc.write_file_atomic(link) { |f| f.write('a'); f.write('b') }
    assert!(File.read(link) == 'ab', 'block form writes content')

    # --- clear_legacy_scratch! removes a symlink, not its target ---
    File.unlink(link)
    File.symlink(victim, link)
    rc.clear_legacy_scratch!
    assert!(!File.exist?(link) && !File.symlink?(link), 'legacy symlink removed')
    assert!(File.read(victim) == 'original', 'legacy cleanup must not touch symlink target')

    # --- per-run directory: unique, readable by Asterisk, removed on cleanup ---
    rc.begin_run!
    dir = rc.run_dir
    assert!(File.directory?(dir) && File.dirname(dir) == tmp, 'run dir created under tmp_dir')
    assert!((File.stat(dir).mode & 0o777) == 0o755, 'run dir is 0755 so asterisk can read audio')
    scratch = rc.scoped_tmp_path('temperature')
    assert!(File.dirname(scratch) == dir, 'scratch files live in run dir')
    File.write(scratch, '72')

    # A child sharing the run dir (weather.rb --weather-subprocess) must not delete it.
    parent_state = %i[@run_id @run_dir @owns_run_dir @scratch_files].map { |v| [v, rc.instance_variable_get(v)] }
    child_env = rc.child_env
    rc.instance_variable_set(:@run_id, nil)
    rc.instance_variable_set(:@run_dir, nil)
    with_env(child_env) do
      rc.ensure_run!
      assert!(rc.run_dir == dir, 'child adopts parent run dir')
      rc.scoped_tmp_path('temperature')
      rc.cleanup!
    end
    assert!(File.exist?(scratch), 'child cleanup leaves parent files in place')
    parent_state.each { |v, val| rc.instance_variable_set(v, val) }

    rc.cleanup!
    assert!(!File.exist?(dir), 'parent cleanup removes run dir')

    rc.begin_run!
    assert!(rc.run_dir != dir, 'each run gets a new directory')
    rc.cleanup!

    # --- cache directory selection ---
    env_cache = File.join(tmp, 'explicit-cache')
    with_env('SAYTIME_CACHE_DIR' => env_cache) do
      assert!(SaytimeWeather::Paths.cache_dir == env_cache, 'SAYTIME_CACHE_DIR wins')
      assert!(SaytimeWeather::Paths.geocode_cache_path('us-77511').start_with?(env_cache), 'caches use cache_dir')
    end

    unless File.directory?(SaytimeWeather::Paths::DEFAULT_CACHE_DIR)
      per_user = File.join(tmp, "saytime-weather-cache-#{Process.uid}")
      assert!(SaytimeWeather::Paths.cache_dir == per_user, 'per-user tmp cache fallback')
      assert!((File.stat(per_user).mode & 0o777) == 0o700, 'per-user cache is private')

      # A symlink planted at the per-user name is never used as the cache dir.
      FileUtils.rm_rf(per_user)
      elsewhere = File.join(tmp, 'elsewhere')
      Dir.mkdir(elsewhere)
      File.symlink(elsewhere, per_user)
      rc.begin_run!
      chosen = SaytimeWeather::Paths.cache_dir
      assert!(chosen != per_user && chosen.start_with?(rc.run_dir), 'symlinked cache dir rejected')
      rc.cleanup!
      File.unlink(per_user)
    end

    assert!(SaytimeWeather::Cache.write_json(File.join(tmp, 'c', 'x.json'), { 'a' => 1 }), 'cache write')
    assert!(SaytimeWeather::Cache.read_json(File.join(tmp, 'c', 'x.json'), 60) == { 'a' => 1 }, 'cache read')
  end
end

# --- HTTP client: redirects do not nest retry loops; Retry-After is honored ---
server = TCPServer.new('127.0.0.1', 0)
port = server.addr[1]
hits = 0
mode = :redirect
srv = Thread.new do
  loop do
    client = server.accept
    hits += 1
    while (line = client.gets) && line != "\r\n"; end
    if mode == :redirect
      client.write("HTTP/1.1 302 Found\r\nLocation: /again\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    else
      client.write("HTTP/1.1 429 Too Many Requests\r\nRetry-After: 2\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    end
    client.close
  rescue IOError, SystemCallError
    break
  end
end

SaytimeWeather::Network.retry_sleep = 0
http = SaytimeWeather::HttpClient.new
$stderr.reopen(File::NULL, 'w') if ENV['QUIET_HTTP']
result = http.get("http://127.0.0.1:#{port}/start", 2, nil, 3)
http.close
assert!(result.nil?, 'redirect loop returns nil')
assert!(hits <= SaytimeWeather::Network.retries * 3, "redirects must not nest retries (#{hits} requests)")

mode = :limited
hits = 0
http = SaytimeWeather::HttpClient.new
slept = []
http.define_singleton_method(:sleep) { |s| slept << s }
http.get("http://127.0.0.1:#{port}/x", 2)
http.close
assert!(slept.all? { |s| s == 2 }, "Retry-After seconds honored (slept #{slept.inspect})")
assert!(http.send(:parse_retry_after, '999') == 999, 'Retry-After seconds parse')
http.instance_variable_set(:@retry_after, 999)
assert!(http.retry_delay == SaytimeWeather::HttpClient::MAX_RETRY_AFTER, 'Retry-After capped')
assert!(http.send(:parse_retry_after, 'garbage').nil?, 'bad Retry-After ignored')
srv.kill
server.close
SaytimeWeather::Network.reset_defaults!

# --- GPS reads respect deadlines without Timeout.timeout ---
class GpsProbe
  include SaytimeWeather::WeatherGps
  def initialize
    @config = {}
    @options = {}
  end

  def warn(*); end
end

g = GpsProbe.new
a, b = UNIXSocket.pair
t0 = monotonic
line = g.send(:read_line_before, a, +'', monotonic + 0.3)
assert!(line.nil? && monotonic - t0 < 2, 'silent gpsd socket times out')
b.write("{\"class\":\"TPV\"}\npartial")
assert!(g.send(:read_line_before, a, buf = +'', monotonic + 1) == "{\"class\":\"TPV\"}\n", 'reads one line')
assert!(buf == 'partial', 'keeps remainder buffered')
a.close
b.close

# Connection setup shares the gps_timeout_seconds budget across all addresses.
assert!(g.send(:ip_literal?, '127.0.0.1') && g.send(:ip_literal?, '::1'), 'IP literals detected')
assert!(!g.send(:ip_literal?, 'gpsd.local'), 'host names are not IP literals')
assert!(g.send(:resolve_before, 'localhost', monotonic + 2).any?, 'localhost resolves via /etc/hosts')

g.define_singleton_method(:resolve_before) { |_h, _d| %w[10.255.255.1 10.255.255.2 10.255.255.3] }
t0 = monotonic
begin
  g.send(:connect_before, 'unreachable.example', 2947, monotonic + 0.5)
  raise 'unreachable gpsd should not connect'
rescue SystemCallError, SocketError
  nil
end
assert!(monotonic - t0 < 1.5, "three dead addresses share one budget (#{(monotonic - t0).round(2)}s)")
g.singleton_class.send(:remove_method, :resolve_before)

# End to end against a fake gpsd: connect, send WATCH, read a TPV fix.
gpsd = TCPServer.new('127.0.0.1', 0)
gpsd_thread = Thread.new do
  c = gpsd.accept
  c.gets
  c.write("{\"class\":\"VERSION\"}\n")
  c.write("{\"class\":\"TPV\",\"mode\":3,\"lat\":29.76,\"lon\":-95.37,\"time\":\"#{Time.now.utc.iso8601}\"}\n")
  sleep 0.5
  c.close
end
g.instance_variable_set(:@config, { 'gpsd_port' => gpsd.addr[1].to_s, 'gps_timeout_seconds' => '3' })
fix = g.send(:read_gps_from_gpsd)
assert!(fix && fix[:lat].round(2) == 29.76 && fix[:lon].round(2) == -95.37, "gpsd fix read (#{fix.inspect})")
gpsd_thread.join(2)
gpsd.close
g.instance_variable_set(:@config, {})

t0 = monotonic
out = g.send(:read_command_output, ['sleep', '10'], 0.3)
assert!(out.nil? && monotonic - t0 < 3, 'hung gpspipe is terminated at the deadline')
assert!(g.send(:read_command_output, ['echo', 'hi'], 2) == "hi\n", 'command output collected')
assert!(g.send(:executable_in_path?, 'sh'), 'PATH lookup finds sh')
assert!(!g.send(:executable_in_path?, 'definitely-not-a-real-binary'), 'PATH lookup misses unknown')

# --- time zone lookup without date(1) ---
class TimeProbe
  include SaytimeWeather::SaytimeTime
end

tp = TimeProbe.new
with_env('TZ' => nil) do
  utc = Time.now.utc
  tokyo = tp.time_in_timezone('Asia/Tokyo')
  if tokyo && File.exist?('/usr/share/zoneinfo/Asia/Tokyo')
    diff = ((tokyo.hour - utc.hour) % 24)
    assert!([9, 8, 10].include?(diff), "Asia/Tokyo is UTC+9 (got +#{diff})")
  end
  assert!(ENV['TZ'].nil?, 'TZ restored after lookup')
  assert!(tp.time_in_timezone('Not/AZone').nil?, 'unknown zone rejected')
  assert!(tp.time_in_timezone('../../etc/passwd').nil?, 'path-like zone rejected')
end

# --- weather.rb trailing `v` works regardless of how the script path appears ---
ws = SaytimeWeather::WeatherScript.allocate
ws.instance_variable_set(:@options, {})
ws.instance_variable_set(:@config, {})
ws.instance_variable_set(:@cli_mode, true)
saved_argv = ARGV.dup
ARGV.replace(%w[77511 v])
assert!(ws.send(:cli_display_only_arg) == 'v', 'display-only from CLI')
ARGV.replace(%w[77511])
assert!(ws.send(:cli_display_only_arg).nil?, 'no v means sound output')
ws.instance_variable_set(:@options, { use_gps: true })
ARGV.replace(%w[v])
assert!(ws.send(:cli_display_only_arg) == 'v', 'display-only with --gps')
ws.instance_variable_set(:@cli_mode, false)
assert!(ws.send(:cli_display_only_arg).nil?, 'in-process runs ignore ARGV')
ARGV.replace(saved_argv)

puts 'hardening_test: ok'
