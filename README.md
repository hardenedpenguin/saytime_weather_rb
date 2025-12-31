# Saytime Weather (Ruby Version)

A Ruby implementation of a time and weather announcement system for Asterisk PBX, designed for radio systems, repeater controllers, and amateur radio applications. Complete rewrite in Ruby with zero external dependencies. Provides automated voice announcements of current time and weather conditions.

**Version 0.0.1**

## 🚀 Features

- **Time Announcements**: 12-hour and 24-hour formats with location-aware timezone support
- **Worldwide Weather**: Postal codes, ICAO airport codes (6000+ airports), or special locations
- **No API Keys Required**: Works immediately after installation
- **Day/Night Detection**: Intelligent conditions (never says "sunny" at 2 AM)
- **Free APIs**: Open-Meteo (worldwide) or NWS (US only) + Nominatim (geocoding)

## 📋 Requirements

- **Ruby 2.7+**
- **Asterisk PBX** (tested with versions 16+)
- **Internet Connection** for weather API access

## 📦 Dependencies

**No external dependencies required!** 

This Ruby version uses only built-in Ruby 2.7+ libraries:
- `json` - Built-in JSON parsing
- `net/http` - Built-in HTTP client
- `uri` - Built-in URI handling
- `optparse` - Built-in command-line parsing
- `tempfile` - Built-in temporary file handling
- `fileutils` - Built-in file operations
- `time` - Built-in time handling
- Custom simple INI parser (no gem needed)

Just copy the files and run - no `bundle install` or `gem install` needed!

## 🛠️ Installation

### Debian Package Installation (Recommended)

Build and install the Debian package:
```bash
cd /home/sources/saytime_weather_rb
make deb
sudo dpkg -i ../saytime-weather-rb_0.0.1-1_all.deb
```

This will:
- Install scripts to `/usr/sbin/` (requires root/sudo to run)
- Install sound files to `/usr/share/asterisk/sounds/en/`
- Create default configuration at `/etc/asterisk/local/weather.ini` (if it doesn't exist)

### Manual Installation

1. Clone or copy the project to your desired location:
```bash
cd /home/sources
git clone <repository> saytime_weather_rb
# or copy the files manually
```

2. Make scripts executable:
```bash
chmod +x /home/sources/saytime_weather_rb/weather.rb
chmod +x /home/sources/saytime_weather_rb/saytime.rb
```

3. Optionally create symlinks for easy access:
```bash
sudo ln -s /home/sources/saytime_weather_rb/weather.rb /usr/local/bin/weather.rb
sudo ln -s /home/sources/saytime_weather_rb/saytime.rb /usr/local/bin/saytime.rb
```

## ⚙️ Configuration

Configuration is **optional** - the system works out of the box. Edit `/etc/asterisk/local/weather.ini` (auto-created on first run):

```ini
[weather]
Temperature_mode = F              # F or C
default_country = us              # ISO country code (us, ca, de, fr, etc.)
process_condition = YES           # YES or NO
weather_provider = openmeteo      # openmeteo (worldwide) or nws (US only)
```

### Weather Provider Options

The `weather_provider` setting allows you to choose between:
- **`openmeteo`** (default): Worldwide coverage, works for all locations
- **`nws`**: US locations only, uses official National Weather Service data (more accurate for US)

**Default behavior**: If `weather_provider` is not set in your existing config, it defaults to `openmeteo`, so your system will continue working exactly as before. No changes required!

**To enable NWS for US locations**, add this line to your `weather.ini`:
```ini
weather_provider = nws
```

**Note**: NWS automatically falls back to Open-Meteo for non-US locations, so you can safely use `nws` even if you occasionally query international locations.

## 🎯 Usage

### saytime.rb - Time and Weather Announcements

```bash
saytime.rb -l <LOCATION_ID> -n <NODE_NUMBER>
```

**Location ID**: Postal code, ICAO airport code (e.g., `KJFK`, `EGLL`), or special location name.

#### Common Options

| Option | Description | Default |
|--------|-------------|---------|
| `-l, --location_id=ID` | Location ID (required when weather enabled) | - |
| `-n, --node_number=NUM` | Node number (required) | - |
| `-d, --default-country CC` | Override default country for weather lookups | - |
| `-s, --silent=NUM` | 0=voice, 1=save both, 2=weather only | 0 |
| `-u, --use_24hour` | 24-hour time format | 12-hour |
| `-v, --verbose` | Verbose output | Off |
| `--dry-run` | Test mode (don't play) | Off |
| `-w, --weather` | Enable weather | On |
| `-g, --greeting` | Enable greetings | On |
| `--help` | Show help | - |

### weather.rb - Standalone Weather Retrieval

```bash
weather.rb <LOCATION_ID> [v]
```

Add `v` for text-only output. Options: `-c` (config), `-d` (country), `-t` (temp mode), `--no-condition`, `-h` (help), `--version`.

**Note**: `-t` means different things in each script:
- `saytime.rb`: `-t` = test mode
- `weather.rb`: `-t` = temperature-mode

### Examples

**Postal codes**:
```bash
saytime.rb -l 77511 -n 1          # US ZIP
saytime.rb -l M5H2N2 -n 1         # Canadian postal
saytime.rb -l 75001 -n 1           # European postal
```

**ICAO airport codes**:
```bash
saytime.rb -l KJFK -n 1           # JFK, New York
saytime.rb -l EGLL -n 1           # Heathrow, London
weather.rb CYYZ v                  # Toronto Pearson
```

**Special locations** (50+ remote locations for DXpeditions):
```bash
saytime.rb -l ALERT -n 1          # Alert, Nunavut (northernmost)
weather.rb HEARD v                 # Heard Island (VK0)
weather.rb BOUVET v                # Bouvet Island (3Y0)
```

**Other options**:
```bash
saytime.rb -l 77511 -n 1 -u  # 24-hour format
saytime.rb -l 77511 -n 1 -s 1     # Save to file
weather.rb -t C KJFK v             # Celsius
```

## ⏰ Automation

### Crontab

```bash
sudo crontab -e
```

**Every hour (3 AM - 11 PM)**:
```cron
00 03-23 * * * /usr/bin/nice -19 /usr/sbin/saytime.rb -l 77511 -n 1 > /dev/null 2>&1
```

**Every 30 minutes (6 AM - 10 PM)**:
```cron
0,30 06-22 * * * /usr/bin/nice -19 /usr/sbin/saytime.rb -l 77511 -n 1 > /dev/null 2>&1
```

### Asterisk Dialplan

```asterisk
[weather-announcement]
exten => 1234,1,Answer()
exten => 1234,2,Exec(/usr/sbin/saytime.rb -l 77511 -n 1)
exten => 1234,3,Hangup()
```

## 🌍 Location Support

- **Postal Codes**: US ZIP (5-digit), Canadian (A1A 1A1), European (5-digit), UK (SW1A1AA), and more
- **ICAO Airport Codes**: 6000+ airports worldwide (4-letter codes like `KJFK`, `EGLL`, `CYYZ`)
- **Special Locations**: 50+ remote locations including:
  - Antarctica stations (SOUTHPOLE, MCMURDO, VOSTOK, etc.)
  - Arctic locations (ALERT, EUREKA, THULE, etc.)
  - DXpedition islands (HEARD, BOUVET, KERGUELEN, etc.)
  - Pacific islands (MIDWAY, WAKE, EASTER, etc.)

**Timezone Feature**: Time announcements automatically match the weather location's timezone using the system's timezone database.

## 🔧 Troubleshooting

**"Could not get coordinates"**:
- Verify postal code format and internet connectivity
- Test: `weather.rb 12345 v`

**No sound output**:
- Check Asterisk: `sudo systemctl status asterisk`
- Test: `saytime.rb -l 12345 -n 1 -v -d`

**Weather not updating**:
- Test API: `curl "https://api.open-meteo.com/v1/forecast?latitude=29.56&longitude=-95.16&current=temperature_2m,weather_code,is_day&temperature_unit=fahrenheit&timezone=auto"`

**Debug mode**:
```bash
saytime.rb -l 12345 -n 1 -v --dry-run  # Verbose + dry-run
weather.rb 12345 v                 # Verbose text output
```

## 📁 File Structure

```
/home/sources/saytime_weather_rb/
├── weather.rb          # Weather retrieval script
├── saytime.rb          # Main announcement script
├── weather.ini.default # Default configuration template
├── Gemfile             # Ruby dependencies (optional, for development)
├── README.md           # This file
└── debian/             # Debian packaging files

/etc/asterisk/local/
└── weather.ini         # Configuration (auto-created from weather.ini.default)

/usr/share/asterisk/sounds/en/
├── a-m.ulaw            # AM indicator
├── p-m.ulaw            # PM indicator
└── wx/                 # Weather sound files

/tmp/                   # Temporary files (temperature, condition.ulaw, timezone)
```

## 🔄 Implementation Details

1. **Timezone Support**: Uses system's timezone database via TZ environment variable and date command
2. **HTTP Library**: Uses Ruby's built-in `Net::HTTP`
3. **Configuration**: Uses custom INI file parser (no external dependencies)

## 📄 License

**Copyright 2026 Jory A. Pratt, W5GLE**

## 🙏 Acknowledgments

- Open-Meteo for free worldwide weather API (https://open-meteo.com)
- National Weather Service for free US weather data (https://weather.gov)
- OpenStreetMap Nominatim for free geocoding (https://nominatim.org)

---

**Made with ❤️ for the amateur radio community**

