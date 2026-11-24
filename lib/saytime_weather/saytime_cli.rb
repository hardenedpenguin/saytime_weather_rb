# frozen_string_literal: true

require 'optparse'

module SaytimeWeather
  module SaytimeCli
    # Split clustered short flags (-mu → -m -u) before OptionParser. Keeps -n546052 intact.
    def expand_short_option_clusters(argv)
      out = []
      argv.each do |arg|
        if !arg.start_with?('--') && (m = arg.match(/\A-([a-zA-Z]{2,})\z/))
          letters = m[1]
          if letters.match?(/\A[a-zA-Z]\d/) || letters.match?(/\Am(playback|localplay)\z/i)
            out << arg
          else
            letters.each_char { |c| out << "-#{c}" }
          end
        else
          out << arg
        end
      end
      out
    end

    # Bare `-m` means "use playback"; leave `-m playback` / `-m localplay` as two tokens for OptionParser.
    def expand_bare_m_flag(argv)
      i = 0
      while i < argv.length
        if argv[i] == '-m'
          nxt = argv[i + 1]
          if nxt.nil? || nxt.start_with?('-') || !%w[playback localplay].include?(nxt.downcase)
            argv[i] = '-mplayback'
          end
        end
        i += 1
      end
    end

    def prepare_argv(argv)
      expanded = expand_short_option_clusters(argv)
      expand_bare_m_flag(expanded)
      expanded
    end

    def parse_options
      ARGV.replace(prepare_argv(ARGV))
      option_parser.parse!
      @options[:node_number] ||= ARGV[0] if ARGV[0]
    end

    # Single definition of the CLI options; --help output is generated from it.
    def option_parser
      @option_parser ||= OptionParser.new do |opts|
        opts.banner = "saytime.rb version #{SaytimeWeather::VERSION}\n\nUsage: saytime.rb [OPTIONS]"
        opts.separator ''
        opts.separator 'Options:'
        opts.summary_width = 24
        opts.summary_indent = '  '

        opts.on('-l', '--location_id=ID',
                'Location ID for weather (optional with --gps or location_source=gps)') do |id|
          @options[:location_id] = id
        end
        opts.on('-n', '--node_number=NUM', 'Node number for announcement (required)') do |num|
          @options[:node_number] = num
        end
        opts.on('-s', '--silent=NUM', Integer, 'Silent mode (default: 0)',
                '0=play (scratch files removed after run)',
                '1=save time+weather to /tmp/current-time.ulaw',
                '2=save weather only to /tmp/current-time.ulaw') do |num|
          @options[:silent] = num
        end
        opts.on('-h', '--help', 'Show this help message') do
          show_usage
          exit 0
        end
        opts.on('-u', '--use_24hour', 'Use 24-hour clock (default: 12-hour)') { @options[:use_24hour] = true }
        opts.on('-v', '--verbose', 'Enable verbose output (default: off)') { @options[:verbose] = true }
        opts.on('--dry-run', "Don't actually play or save files (default: off)") { @options[:dry_run] = true }
        opts.on('-d', '--default-country CC',
                'Override default country for weather (us, ca, fr, de, uk, etc.)') do |cc|
          @options[:default_country] = cc
        end
        opts.on('-c', '--config FILE', 'Path to weather.ini for weather lookups') { |f| @options[:config_file] = f }
        opts.on('--gps', 'Use GPS via gpsd (or set location_source = gps in weather.ini)') do
          @options[:use_gps] = true
        end
        opts.on('--weather-subprocess', 'Run weather.rb as subprocess (default: in-process)') do
          @options[:weather_subprocess] = true
        end
        opts.on('-t', '--test', 'Log playback command instead of executing (default: off)') do
          @options[:test_mode] = true
        end
        opts.on('-w', '--weather', 'Enable weather announcements (default: on)') { @options[:weather_enabled] = true }
        opts.on('--no-weather', 'Disable weather announcements') { @options[:weather_enabled] = false }
        opts.on('-g', '--greeting', 'Enable greeting messages (default: on)') { @options[:greeting_enabled] = true }
        opts.on('--no-greeting', 'Disable greeting messages') { @options[:greeting_enabled] = false }
        opts.on('-m', '--method=METHOD',
                'Use -m alone for playback, or pass localplay|playback (default: localplay)') do |method|
          @options[:play_method] = method.downcase
        end
        opts.on('--sound-dir=DIR', 'Use custom sound directory',
                "(default: #{SaytimeWeather::Paths.asterisk_sounds_en})") do |dir|
          @options[:custom_sound_dir] = dir
        end
        opts.on('--log=FILE', 'Log to specified file (default: none)') { |file| @options[:log_file] = file }

        opts.separator ''
        opts.separator 'Location ID: Any postal code worldwide, lat,lon coordinates, or GPS via --gps'
        opts.separator '  - US: 77511, 10001, 90210'
        opts.separator '  - International: 75001 (Paris), SW1A1AA (London), etc.'
        opts.separator '  - Coordinates: 48.8566,2.3522'
        opts.separator '  - GPS: saytime.rb --gps -n 546054 (requires gpsd)'
        opts.separator ''
        opts.separator 'Examples:'
        opts.separator '  saytime.rb -l 77511 -n 546054'
        opts.separator '  saytime.rb -l 77511 -n 546054 -s 1'
        opts.separator '  saytime.rb -l 77511 -n 546054 -u'
        opts.separator ''
        opts.separator "Configuration in #{SaytimeWeather::Paths.config_path}:"
        opts.separator '  - Temperature_mode: F/C (default: F)'
        opts.separator '  - process_condition: YES/NO (default: YES)'
        opts.separator ''
        opts.separator 'Time zone: the weather location\'s time zone is used; a TZ environment variable,'
        opts.separator '  when set, overrides it (unset TZ in cron to announce location-local time).'
        opts.separator ''
        opts.separator 'Note: Free providers need no API key; WeatherAPI requires weatherapi_key when weather_provider = weatherapi.'
      end
    end

    def show_usage
      puts option_parser.help
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

      if @options[:weather_enabled] && !@options[:location_id] && !gps_weather_enabled?
        error('Location ID (postal code) is required when weather is enabled')
        error('  Use --gps or set location_source = gps in weather.ini for GPS location')
        error('  Use --no-weather (double dash) to disable weather announcements')
        error('  Example: saytime.rb --no-weather -n 546054')
        exit 1
      end

      if @options[:use_gps] && @options[:location_id] && !@options[:location_id].to_s.empty?
        warn('Both --gps and -l were given; using -l for weather location (GPS ignored)')
      end

      if @options[:custom_sound_dir] && !Dir.exist?(@options[:custom_sound_dir])
        error("Custom sound directory does not exist: #{@options[:custom_sound_dir]}")
        exit 1
      end
    end
  end
end
