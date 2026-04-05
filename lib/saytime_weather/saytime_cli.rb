# frozen_string_literal: true

require 'optparse'

module SaytimeWeather
  module SaytimeCli
    def parse_options
      parser = OptionParser.new do |opts|
        opts.banner = "saytime.rb version #{SaytimeWeather::VERSION}\n\nUsage: #{File.basename($PROGRAM_NAME)} [OPTIONS]\n\n"

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

        opts.on('-m', '--method=METHOD', 'Playback method: localplay or playback (default: localplay)') do |method|
          @options[:play_method] = method.downcase
        end

        opts.on('--sound-dir=DIR', 'Use custom sound directory') do |dir|
          @options[:custom_sound_dir] = dir
        end

        opts.on('--log=FILE', 'Log to specified file') do |file|
          @options[:log_file] = file
        end
      end

      parser.parse!

      @options[:node_number] ||= ARGV[0] if ARGV[0]
    end

    def show_usage
      puts "saytime.rb version #{SaytimeWeather::VERSION}\n\n"
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
      puts "  -m, --method=METHOD     Playback method: localplay or playback (default: localplay)"
      puts "      --sound-dir=DIR     Use custom sound directory"
      puts "                          (default: #{SaytimeWeather::Paths.asterisk_sounds_en})"
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
  end
end
