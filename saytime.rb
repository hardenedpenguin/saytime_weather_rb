#!/usr/bin/env ruby
# frozen_string_literal: true

# saytime.rb - Time and weather announcement script (Ruby version)
# Copyright 2026 Jory A. Pratt, W5GLE
#
# - Announces current time (12-hour or 24-hour format)
# - Optionally announces weather conditions
# - Combines sound files and plays via Asterisk

require 'optparse'
require 'fileutils'
require 'time'

VERSION = '0.0.2'
TMP_DIR = '/tmp'
BASE_SOUND_DIR = '/usr/share/asterisk/sounds/en'
WEATHER_SCRIPT = File.join(File.dirname(__FILE__), 'weather.rb')
DEFAULT_VERBOSE = false
DEFAULT_DRY_RUN = false
DEFAULT_TEST_MODE = false
DEFAULT_WEATHER_ENABLED = true
DEFAULT_24HOUR = false
DEFAULT_GREETING = true
ASTERISK_BIN = '/usr/sbin/asterisk'
DEFAULT_PLAY_METHOD = 'localplay'
PLAY_DELAY = 5
FILE_BUFFER_SIZE = 8192

class SaytimeScript
  attr_reader :options, :config, :critical_error

  def initialize
    @options = {
      location_id: nil,
      node_number: nil,
      silent: 0,
      use_24hour: DEFAULT_24HOUR,
      verbose: DEFAULT_VERBOSE,
      dry_run: DEFAULT_DRY_RUN,
      test_mode: DEFAULT_TEST_MODE,
      weather_enabled: DEFAULT_WEATHER_ENABLED,
      greeting_enabled: DEFAULT_GREETING,
      custom_sound_dir: nil,
      log_file: nil,
      play_method: DEFAULT_PLAY_METHOD,
      default_country: nil
    }
    @config = {}
    @critical_error = false
    parse_options
    load_config
  end

  def parse_options
    parser = OptionParser.new do |opts|
      opts.banner = "saytime.rb version #{VERSION}\n\nUsage: #{File.basename($PROGRAM_NAME)} [OPTIONS]\n\n"
      
      opts.on('-l', '--location_id=ID', 'Location ID for weather (required when weather enabled)') do |id|
        @options[:location_id] = id
      end
      
      opts.on('-n', '--node_number=NUM', 'Node number for announcement (required)') do |num|
        @options[:node_number] = num
      end
      
      opts.on('-s', '--silent=NUM', Integer, 'Silent mode: 0=voice, 1=save both, 2=weather only (default: 0)') do |num|
        @options[:silent] = num
      end
      
      opts.on('-u', '--use_24hour', 'Use 24-hour clock (default: 12-hour)') do
        @options[:use_24hour] = true
      end
      
      opts.on('-h', '--help', 'Show this help message') do
        show_usage
        exit 0
      end
      
      opts.on('-v', '--verbose', 'Enable verbose output') do
        @options[:verbose] = true
      end
      
      opts.on('--dry-run', "Don't actually play or save files") do
        @options[:dry_run] = true
      end
      
      opts.on('-d', '--default-country CC', 'Override default country for weather lookups (us, ca, fr, de, uk, etc.)') do |cc|
        @options[:default_country] = cc
      end
      
      opts.on('-t', '--test', 'Log playback command instead of executing') do
        @options[:test_mode] = true
      end
      
      opts.on('-w', '--weather', 'Enable weather announcements (default: on)') do
        @options[:weather_enabled] = true
      end
      
      opts.on('--no-weather', 'Disable weather announcements') do
        @options[:weather_enabled] = false
      end
      
      opts.on('-g', '--greeting', 'Enable greeting messages (default: on)') do
        @options[:greeting_enabled] = true
      end
      
      opts.on('--no-greeting', 'Disable greeting messages') do
        @options[:greeting_enabled] = false
      end
      
      opts.on('-m', '--method', 'Enable playback method (default: localplay)') do
        @options[:play_method] = 'playback'
      end
      
      opts.on('--sound-dir=DIR', 'Use custom sound directory') do |dir|
        @options[:custom_sound_dir] = dir
      end
      
      opts.on('--log=FILE', 'Log to specified file') do |file|
        @options[:log_file] = file
      end
    end
    
    parser.parse!
    
    # Node number can also be provided as positional argument
    @options[:node_number] ||= ARGV[0] if ARGV[0]
  end

  def show_usage
    puts "saytime.rb version #{VERSION}\n\n"
    puts "Usage: #{File.basename($PROGRAM_NAME)} [OPTIONS]\n\n"
    puts "Options:"
    puts "  -l, --location_id=ID    Location ID for weather (default: none)"
    puts "  -n, --node_number=NUM   Node number for announcement (required)"
    puts "  -s, --silent=NUM        Silent mode (default: 0)"
    puts "                          0=voice, 1=save time+weather, 2=save weather only"
    puts "  -h, --help              Show this help message"
    puts "  -u, --use_24hour        Use 24-hour clock (default: 12-hour)"
    puts "  -v, --verbose           Enable verbose output (default: off)"
    puts "      --dry-run            Don't actually play or save files (default: off)"
    puts "  -d, --default-country CC Override default country for weather (us, ca, fr, de, uk, etc.)"
    puts "  -t, --test              Log playback command instead of executing (default: off)"
    puts "  -w, --weather           Enable weather announcements (default: on)"
    puts "      --no-weather        Disable weather announcements"
    puts "  -g, --greeting          Enable greeting messages (default: on)"
    puts "      --no-greeting       Disable greeting messages"
    puts "  -m, --method            Enable playback mode (default: localplay)"
    puts "      --sound-dir=DIR     Use custom sound directory"
    puts "                          (default: /usr/share/asterisk/sounds/en)"
    puts "      --log=FILE          Log to specified file (default: none)"
    puts "      --help              Show this help message and exit\n\n"
    puts "Location ID: Any postal code worldwide"
    puts "  - US: 77511, 10001, 90210"
    puts "  - International: 75001 (Paris), SW1A1AA (London), etc.\n\n"
    puts "Examples:"
    puts "  ruby saytime.rb -l 77511 -n 546054"
    puts "  ruby saytime.rb -l 77511 -n 546054 -s 1"
    puts "  ruby saytime.rb -l 77511 -n 546054 -u\n\n"
    puts "Configuration in /etc/asterisk/local/weather.ini:"
    puts "  - Temperature_mode: F/C (default: F)"
    puts "  - process_condition: YES/NO (default: YES)\n\n"
    puts "Note: No API keys required! Uses system time and weather.rb for weather.\n"
  end

  def load_config
    config_file = '/etc/asterisk/local/weather.ini'
    if File.exist?(config_file)
      begin
        ini = parse_ini_file(config_file)
        @config = ini['weather'] if ini && ini['weather']
      rescue => e
        warn("Failed to load config file: #{e.message}")
      end
    end
    
    @config['Temperature_mode'] ||= 'F'
    @config['process_condition'] ||= 'YES'
  end

  def validate_options
    unless @options[:play_method] =~ /^(localplay|playback)$/
      error("Invalid play method: #{@options[:play_method]} (must be 'localplay' or 'playback')")
      exit 1
    end
    
    unless @options[:node_number]
      show_usage
      exit 1
    end
    
    unless @options[:node_number] =~ /^\d+$/
      error("Invalid node number format: #{@options[:node_number]}")
      exit 1
    end
    
    unless (0..2).include?(@options[:silent])
      error("Invalid silent value: #{@options[:silent]} (must be 0, 1, or 2)")
      exit 1
    end
    
    if @options[:weather_enabled] && !@options[:location_id]
      error("Location ID (postal code) is required when weather is enabled")
      error("  Use --no-weather (double dash) to disable weather announcements")
      error("  Example: saytime.rb --no-weather -n 546054")
      exit 1
    end
    
    if @options[:custom_sound_dir] && !Dir.exist?(@options[:custom_sound_dir])
      error("Custom sound directory does not exist: #{@options[:custom_sound_dir]}")
      exit 1
    end
  end

  def run
    validate_options
    
    # Process weather FIRST so timezone file is created before getting time
    weather_sound_files = process_weather(@options[:location_id])
    
    # Now get time (will use timezone from weather.rb if available)
    now = get_current_time(@options[:location_id])
    
    time_sound_files = process_time(now, @options[:use_24hour])
    
    output_file = tmp_file('current-time.ulaw')
    final_sound_files = combine_sound_files(time_sound_files, weather_sound_files)
    
    if @options[:dry_run]
      info("Dry run mode - would play: #{final_sound_files}")
      exit 0
    end
    
    if final_sound_files && !final_sound_files.strip.empty?
      create_output_file(final_sound_files, output_file)
    end
    
    if @options[:silent] == 0
      play_announcement(@options[:node_number], output_file)
      cleanup_files(output_file, @options[:weather_enabled], @options[:silent])
    elsif [1, 2].include?(@options[:silent])
      info("Saved sound file to #{output_file}")
      cleanup_files(nil, @options[:weather_enabled], @options[:silent])
    end
    
    exit @critical_error ? 1 : 0
  end

  def get_current_time(location_id)
    timezone = nil
    
    # Priority 1: Check TZ environment variable (allows users to override with UTC, etc.)
    if ENV['TZ'] && !ENV['TZ'].empty?
      timezone = ENV['TZ'].strip
    # Priority 2: Check if weather.rb saved a timezone file
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
    
    # Use timezone if we have one
    if timezone && !timezone.empty?
      begin
        # Sanitize timezone to prevent shell injection (only allow alphanumeric, /, _, -, +, :)
        sanitized_tz = timezone.gsub(/[^a-zA-Z0-9\/_\-+: ]/, '')
        if sanitized_tz.empty? || sanitized_tz != timezone
          # Invalid timezone format, fall through to system local time
        else
          # Use system's date command to get hour and minute in specified timezone
          # Use environment variable instead of shell interpolation for safety
          time_parts = nil
          IO.popen({ 'TZ' => sanitized_tz }, ['date', '+%H %M %S']) do |io|
            time_parts = io.read.strip
          end
          
          if $?.success? && time_parts && !time_parts.empty?
            parts = time_parts.split.map(&:to_i)
            if parts.length >= 2
              hour, minute, second = parts[0], parts[1], (parts[2] || 0)
              # Get current date (we only care about time for announcements)
              now = Time.now
              # Create a Time object with the timezone-specific hour and minute
              # Note: This creates a local time object, but with the correct hour/minute
              time = Time.new(now.year, now.month, now.day, hour, minute, second)
              return time
            end
          end
        end
      rescue => e
        # Fall through to system local time
      end
    end
    
    # Fall back to system local time
    Time.now
  end

  def process_time(now, use_24hour)
    files = []
    sound_dir = @options[:custom_sound_dir] || BASE_SOUND_DIR
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
        files << add_sound_file("#{sound_dir}/digits/0.ulaw", @missing_files) if minute < 10
        files << format_number(minute, sound_dir)
      end
      am_pm = hour < 12 ? 'a-m' : 'p-m'
      files << add_sound_file("#{sound_dir}/digits/#{am_pm}.ulaw", 0)
    end
    
    warn("#{@missing_files} sound file(s) missing. Run with -v for details.") if @missing_files > 0 && !@options[:verbose]
    
    files.join(' ')
  end

  def process_weather(location_id)
    return '' unless @options[:weather_enabled] && location_id
    temp_file_to_clean = tmp_file('temperature')
    weather_condition_file_to_clean = tmp_file('condition.ulaw')
    File.unlink(temp_file_to_clean) if File.exist?(temp_file_to_clean)
    File.unlink(weather_condition_file_to_clean) if File.exist?(weather_condition_file_to_clean)
    
    # Validate location_id
    unless location_id =~ /^[a-zA-Z0-9\s\-_]+$/
      error("Invalid location ID format. Only alphanumeric characters, spaces, hyphens, and underscores are allowed.")
      error("  Location: #{location_id}")
      @critical_error = true
      return ''
    end
    
    # Execute weather script (works if executable with shebang, or via ruby)
    weather_args = [location_id]
    weather_args = ['-d', @options[:default_country], location_id] if @options[:default_country]
    
    if File.executable?(WEATHER_SCRIPT)
      weather_result = system(WEATHER_SCRIPT, *weather_args)
    else
      weather_result = system('ruby', WEATHER_SCRIPT, *weather_args)
    end
    
    unless weather_result
      exit_code = $?.exitstatus
      error("Weather script failed:")
      error("  Location: #{location_id}")
      error("  Script: #{WEATHER_SCRIPT}")
      error("  Exit code: #{exit_code}")
      error("  Hint: Check that weather.rb is installed and location ID is valid")
      @critical_error = true
      return ''
    end
    
    temp_file = tmp_file('temperature')
    weather_condition_file = tmp_file('condition.ulaw')
    sound_dir = @options[:custom_sound_dir] || BASE_SOUND_DIR
    
    files = ''
    if File.exist?(temp_file)
      temp = File.read(temp_file).strip
      
      required_files = [
        "#{sound_dir}/silence/1.ulaw",
        "#{sound_dir}/wx/weather.ulaw",
        "#{sound_dir}/wx/conditions.ulaw",
        weather_condition_file,
        "#{sound_dir}/wx/temperature.ulaw",
        "#{sound_dir}/wx/degrees.ulaw"
      ]
      
      missing_count = 0
      required_files.each do |file|
        next if file == weather_condition_file  # Generated file
        unless File.exist?(file)
          warn("Weather sound file not found: #{file}") if @options[:verbose]
          missing_count += 1
        end
      end
      
      if missing_count > 0 && @options[:verbose]
        warn("#{missing_count} weather sound file(s) missing. Announcement may be incomplete.")
      end
      
      files = "#{sound_dir}/silence/1.ulaw " \
              "#{sound_dir}/wx/weather.ulaw " \
              "#{sound_dir}/wx/conditions.ulaw #{weather_condition_file} " \
              "#{sound_dir}/wx/temperature.ulaw "
      
      temp_value = temp.to_i
      if temp_value < 0
        files += add_sound_file("#{sound_dir}/digits/minus.ulaw", 0)
        temp_value = temp_value.abs
      end
      
      files += format_number(temp_value, sound_dir)
      files += " #{sound_dir}/wx/degrees.ulaw "
    else
      error("Temperature file not found after running weather script")
      error("  Expected: #{temp_file}")
      error("  Hint: Check that weather.rb completed successfully")
    end
    
    files
  end

  def format_number(num, sound_dir)
    files = ''
    abs_num = num.abs
    
    return "#{sound_dir}/digits/0.ulaw " if abs_num == 0
    
    # Handle hundreds
    if abs_num >= 100
      hundreds = abs_num / 100
      files += "#{sound_dir}/digits/#{hundreds}.ulaw "
      files += "#{sound_dir}/digits/hundred.ulaw "
      abs_num %= 100
      return files if abs_num == 0
    end
    
    # Handle numbers less than 20
    if abs_num < 20
      files += "#{sound_dir}/digits/#{abs_num}.ulaw "
    else
      # Handle tens and ones
      tens = (abs_num / 10) * 10
      ones = abs_num % 10
      files += "#{sound_dir}/digits/#{tens}.ulaw "
      files += "#{sound_dir}/digits/#{ones}.ulaw " if ones > 0
    end
    
    files
  end

  def combine_sound_files(time_files, weather_files)
    if @options[:silent] == 0 || @options[:silent] == 1
      "#{time_files} #{weather_files}"
    elsif @options[:silent] == 2
      weather_files
    else
      ''
    end
  end

  def create_output_file(input_files, output_file)
    begin
      File.open(output_file, 'wb') do |out|
        files = input_files.split(/\s+/).select { |f| f =~ /\.ulaw$/ }
        files_processed = 0
        
        files.each do |file|
          next unless file
          
          # Validate file path is safe
          unless is_safe_path(file)
            warn("Skipping potentially unsafe file path: #{file}")
            next
          end
          
          if File.exist?(file)
            File.open(file, 'rb') do |in_file|
              while chunk = in_file.read(FILE_BUFFER_SIZE)
                out.write(chunk)
              end
            end
            files_processed += 1
          else
            warn("Sound file not found: #{file}")
            warn("  Expected location: #{file}")
            warn("  Check that sound files are installed in the sound directory")
          end
        end
        
        if files_processed == 0
          raise 'No valid sound files were processed'
        end
        
      end
    rescue => e
      error("Failed to create output file:")
      error("  Output: #{output_file}")
      error("  Error: #{e.message}")
      error("  Hint: Check file permissions and disk space")
      @critical_error = true
    end
  end

  def play_announcement(node, asterisk_file)
    asterisk_file = asterisk_file.sub(/\.ulaw$/, '')
    
    unless node =~ /^\d+$/
      error("Invalid node number format: #{node}")
      @critical_error = true
      return
    end
    
    unless @options[:play_method] =~ /^(localplay|playback)$/
      error("Invalid play method: #{@options[:play_method]}")
      @critical_error = true
      return
    end
    
    # Sanitize asterisk_file path
    asterisk_file = asterisk_file.gsub(/[^a-zA-Z0-9\/\-_\.]/, '')
    
    if @options[:test_mode]
      info("Test mode - would execute: rpt #{@options[:play_method]} #{node} #{asterisk_file}")
      return
    end
    
    asterisk_cmd = "rpt #{@options[:play_method]} #{node} #{asterisk_file}"
    
    result = system(ASTERISK_BIN, '-rx', asterisk_cmd)
    unless result
      exit_code = $?.exitstatus
      error("Failed to play announcement:")
      error("  Method: #{@options[:play_method]}")
      error("  Node: #{node}")
      error("  File: #{asterisk_file}")
      error("  Exit code: #{exit_code}")
      error("  Hint: Verify Asterisk is running and node number is correct")
      @critical_error = true
    end
    sleep PLAY_DELAY
  end

  def tmp_file(name)
    File.join(TMP_DIR, name)
  end

  def is_safe_path(file)
    return false if file.include?('..')
    return true if file.start_with?('/usr/share/asterisk/sounds')
    return true if file.start_with?('/tmp/')
    false
  end

  def cleanup_files(file_to_delete, weather_enabled, silent)
    if file_to_delete && silent == 0
      File.unlink(file_to_delete) if File.exist?(file_to_delete)
    end
    
    if weather_enabled && [0, 1, 2].include?(silent)
      weather_files = [
        tmp_file('temperature'),
        tmp_file('condition.ulaw'),
        tmp_file('timezone')
      ]
      
      weather_files.each do |file|
        File.unlink(file) if File.exist?(file)
      end
    end
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

  def parse_ini_file(file_path)
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

  def info(msg)
    puts msg
  end

  def warn(msg)
    $stderr.puts "WARNING: #{msg}"
  end

  def error(msg)
    $stderr.puts "ERROR: #{msg}"
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  script = SaytimeScript.new
  script.run
end

