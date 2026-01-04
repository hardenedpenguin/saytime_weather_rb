# Saytime Weather (Ruby Version)

A Ruby implementation of a time and weather announcement system for Asterisk PBX, designed for radio systems, repeater controllers, and amateur radio applications. Complete rewrite in Ruby with zero external dependencies.

> **⚠️ WARNING:** Do not install this package alongside any other version of saytime_weather. This Ruby implementation is a complete replacement and conflicts with other implementations. Please uninstall any existing saytime_weather packages before installing this one.

## Requirements

- Ruby 2.7+
- Asterisk PBX (tested with versions 16+)
- Internet connection for weather API access

## Installation

```bash
cd /tmp
wget https://github.com/hardenedpenguin/saytime_weather_rb/releases/download/v0.0.1/saytime-weather-rb_0.0.1-1_all.deb
sudo apt install ./saytime-weather-rb_0.0.1-1_all.deb
```

## Configuration

The configuration file is located at `/etc/asterisk/local/weather.ini`:

```ini
[weather]
Temperature_mode = F
process_condition = YES
default_country = us
weather_provider = openmeteo
```

- **Temperature_mode**: `F` for Fahrenheit or `C` for Celsius (default: `F`)
- **process_condition**: `YES` to process weather conditions, `NO` to skip (default: `YES`)
- **default_country**: ISO country code for postal code lookups (default: `us`)
- **weather_provider**: `openmeteo` for worldwide or `nws` for US only (default: `openmeteo`)

## Usage

### Weather Script

```bash
sudo /usr/sbin/weather.rb <location>
```

Examples:
```bash
sudo /usr/sbin/weather.rb 75001                    # US postal code
sudo /usr/sbin/weather.rb KDFW                     # ICAO airport code
sudo /usr/sbin/weather.rb --default-country fr 75001  # International
```

Options: `-d, --default-country CC`, `-c, --config-file FILE`, `-h, --help`

### Time Script

```bash
sudo /usr/sbin/saytime.rb -l <location_id> -n <node_number> [options]
```

Examples:
```bash
sudo /usr/sbin/saytime.rb -l 75001 -n 123456       # Basic announcement
sudo /usr/sbin/saytime.rb -l 75001 -n 123456 -u    # 24-hour format
sudo /usr/sbin/saytime.rb -l 75001 -n 123456 --no-weather  # Time only
TZ=UTC /usr/sbin/saytime.rb -l 75001 -n 123456 --no-weather  # UTC time
```

Required: `-l, --location_id=ID`, `-n, --node_number=NUM`

Common options: `-u, --use_24hour`, `-d, --default-country CC`, `-v, --verbose`, `--dry-run`, `--no-weather`

**Important:** The `-l, --location_id` option is a `saytime.rb` option (not a `weather.rb` option). When you specify `-l <location>`, `saytime.rb` automatically passes this location to `weather.rb` internally. The `-d, --default-country` option is passed through from `saytime.rb` to `weather.rb` when calling the weather script. You cannot use `-l` directly with `weather.rb` - it only accepts location as a positional argument.

**Timezone:** When weather is enabled (default), the timezone is determined by `weather.rb` based on the location's weather data. When using `--no-weather`, `weather.rb` is not called and the timezone falls back to the system's local time. You can override this behavior by setting the `TZ` environment variable when running `saytime.rb` (e.g., `TZ=UTC saytime.rb -l 75001 -n 123456` for UTC time, or `TZ=Europe/London saytime.rb -l 75001 -n 123456` for London time). The `TZ` environment variable takes precedence over all other timezone sources.

Run with `--help` for complete option list.

## Asterisk Dialplan

```ini
[time_weather]
exten => s,1,NoOp(Time and Weather Announcement)
same => n,Set(NODENUM=${EXTEN})
same => n,System(/usr/sbin/saytime.rb -l 75001 -n ${NODENUM})
same => n,Hangup()
```

## Scheduled Announcements

```bash
# Run from 6 AM to 11 PM at the top of each hour
0 6-23 * * * /usr/sbin/saytime.rb -l 75001 -n 123456
```

## Migration from weather.pl

If you're using supermon-ng or other scripts that call `weather.pl`, update them to use `weather.rb`:

```bash
sudo sed -i 's/weather\.pl/weather.rb/g' /var/www/html/supermon-ng/user_files/sbin/ast_node_status_update.py
```

## Links

- **Homepage**: https://github.com/hardenedpenguin/saytime_weather_rb
- **Releases**: https://github.com/hardenedpenguin/saytime_weather_rb/releases
- **License**: GPL-3+

## Maintainer

Jory A. Pratt (W5GLE) <geekypenguin@gmail.com>
