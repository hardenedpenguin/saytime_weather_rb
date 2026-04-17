# Saytime Weather (Ruby Version)

![GitHub total downloads](https://img.shields.io/github/downloads/hardenedpenguin/saytime_weather_rb/total?style=flat-square)

A Ruby implementation of a time and weather announcement system for Asterisk PBX, designed for radio systems, repeater controllers, and amateur radio applications. Complete rewrite in Ruby with zero external dependencies.

> **⚠️ WARNING:** Do not install this package alongside any other version of saytime_weather. This Ruby implementation is a complete replacement and conflicts with other implementations. Please uninstall any existing saytime_weather packages before installing this one.

## Requirements

- Ruby 2.7+
- Asterisk PBX (tested with versions 16+)
- Internet connection for weather API access

## Layout (source and Debian package)

- **`weather.rb`**, **`saytime.rb`** — entry scripts (`/usr/sbin/` when installed).
- **`lib/saytime_weather/`** — shared code: version, paths, HTTP client, API URL helpers, tunable network defaults.
- **`data/special_locations.json`** — named remote / polar / island coordinates for postal-style lookups (`/usr/share/saytime-weather-rb/data/` when installed).

### Source tree vs installed package

`weather.rb` and `saytime.rb` set `SaytimeWeather.root` from the script location so library and data paths stay correct in both layouts:

| Layout | Package root (`SaytimeWeather.root`) | Where `lib/` and `data/` load from |
|--------|--------------------------------------|-------------------------------------|
| **Repository** (clone or extract; `lib/saytime_weather/` next to the scripts) | The directory containing the entry script (usually the repo root) | `./lib/` and `./data/` next to `weather.rb` / `saytime.rb` |
| **Debian `.deb`** (`/usr/sbin/weather.rb`, `/usr/sbin/saytime.rb`) | `/usr/share/saytime-weather-rb/` | `/usr/share/saytime-weather-rb/lib/` and `.../data/`; `/usr/sbin/` holds only the thin wrappers |

You can run `./weather.rb` or `./saytime.rb` from a checkout without installing the package, as long as the usual `lib/` layout is present beside the scripts.

Optional **environment variables** (defaults suit ASL3 / typical Linux installs):

| Variable | Purpose |
|----------|---------|
| `SAYTIME_TMP` | Directory for temperature/timezone scratch files (default `/tmp`) |
| `WEATHER_CONFIG` | Path to `weather.ini` (default `/etc/asterisk/local/weather.ini`) |
| `SAYTIME_SOUND_ROOT` | Base Asterisk English sounds directory (default `/usr/share/asterisk/sounds/en`) |
| `ASTERISK_BIN` | Asterisk binary for playback (default `/usr/sbin/asterisk`) |

Optional **`weather.ini`** keys under `[weather]` for HTTP behavior: `http_timeout_short`, `http_timeout_long`, `nominatim_delay`, `http_get_retries`, `http_get_retry_sleep`, `airports_cache_max_age_seconds`, `airports_data_url`. See the commented block in the default config under `/usr/share/saytime-weather-rb/weather.ini`.

## Installation

```bash
cd /tmp
wget https://github.com/hardenedpenguin/saytime_weather_rb/releases/download/v0.0.9/saytime-weather-rb_0.0.9-1_all.deb
sudo apt install ./saytime-weather-rb_0.0.9-1_all.deb
```

## Upgrading

When upgrading from a previous version:

> **⚠️ IMPORTANT:** The `/etc/asterisk/local/weather.ini` configuration file is **not automatically updated** during package upgrades. If new configuration options are added in a new release, you will need to manually add them to your existing `weather.ini` file.

To add new options:
1. Check the default configuration file at `/usr/share/saytime-weather-rb/weather.ini` for new options
2. Compare with your existing `/etc/asterisk/local/weather.ini`
3. Add any missing options to your configuration file

Example: If upgrading to version 0.0.4, you may want to add the new weather data options:
```ini
show_precipitation = NO
show_wind = NO
show_pressure = NO
show_humidity = NO
show_zero_precip = NO
precip_trace_mm = 0.10
```

## Configuration

The configuration file is located at `/etc/asterisk/local/weather.ini`:

```ini
[weather]
Temperature_mode = F
process_condition = YES
default_country = us
weather_provider = openmeteo
show_precipitation = NO
show_wind = NO
show_pressure = NO
show_humidity = NO
show_zero_precip = NO
precip_trace_mm = 0.10
```

### Basic Options

- **Temperature_mode**: `F` for Fahrenheit or `C` for Celsius (default: `F`)
- **process_condition**: `YES` to process weather conditions, `NO` to skip (default: `YES`)
- **default_country**: ISO country code for postal code lookups (default: `us`)
- **weather_provider**: `openmeteo` for worldwide or `nws` for US only (default: `openmeteo`)

### Additional Weather Data

The following options control display of additional weather information. Units are automatically selected based on `Temperature_mode`:

- **show_precipitation**: `YES` to show precipitation (default: `NO`)
  - F mode: inches (in)
  - C mode: millimeters (mm)
- **show_wind**: `YES` to show wind speed and direction (default: `NO`)
  - F mode: miles per hour (mph)
  - C mode: kilometers per hour (km/h)
- **show_pressure**: `YES` to show barometric pressure (default: `NO`)
  - F mode: inches of mercury (inHG)
  - C mode: hectopascals (hPa)
- **show_humidity**: `YES` to show relative humidity percentage (default: `NO`)
  - Displays as "65% RH"
- **show_zero_precip**: `YES` to show precipitation even when zero (default: `NO`)
  - If `NO`, precipitation is only shown when there's measurable precipitation
- **precip_trace_mm**: Minimum precipitation threshold in millimeters (default: `0.10`)
  - Precipitation below this value is hidden unless `show_zero_precip = YES`

## Usage

### Weather Script

```bash
sudo /usr/sbin/weather.rb <location>
```

Examples:
```bash
sudo /usr/sbin/weather.rb 75001                    # US postal code
sudo /usr/sbin/weather.rb DFW                      # IATA airport code (3 letters)
sudo /usr/sbin/weather.rb KDFW                     # ICAO airport code (4 letters)
sudo /usr/sbin/weather.rb --default-country fr 75001  # International
sudo /usr/sbin/weather.rb 75001 v                  # Display text only (verbose mode)
```

Options: `-d, --default-country CC`, `-c, --config-file FILE`, `-t, --temperature-mode M`, `--no-condition`, `-v, --verbose`, `-h, --help`

**IATA → ICAO:** The script loads the public [Our Airports](https://ourairports.com/data.html) CSV over HTTPS and caches it under `/tmp/saytime-weather-ourairports.csv` (refreshed when older than seven days). If the registry cannot be fetched and there is no cache yet, unknown three-letter codes fall back to `K` + IATA (US-style), which may be wrong outside the US.

### Output Format

The weather script outputs a formatted string with temperature, condition, and optionally additional data:

```
75°F, 24°C / Clear
75°F, 24°C / 65% RH / Clear / Precip 0.25 in / Wind 15 mph SW (gust 22) / 29.92 inHG
```

The format includes:
- Temperature in both Fahrenheit and Celsius
- Relative humidity (if `show_humidity = YES`)
- Weather condition
- Precipitation (if `show_precipitation = YES`)
- Wind speed, direction, and gusts (if `show_wind = YES`)
- Barometric pressure (if `show_pressure = YES`)

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

**12-hour format:** Times like 2:06 are announced as "two oh six" using `letters/o.ulaw` when present, otherwise the digit zero is used.

### When the announced time is in a timezone vs system local time

| Situation | What time is announced |
|-----------|------------------------|
| **`TZ` is set** (e.g. `TZ=UTC`, `TZ=Europe/London`) | Time in that timezone. `TZ` overrides everything. |
| **Weather on, location = postal code**, weather ran successfully | Time in the **location’s timezone** (from Open-Meteo or NWS; written to `/tmp/timezone` by `weather.rb`). |
| **Weather on, location = ICAO or IATA** (e.g. KDFW, JFK) | **System local time.** METAR/aviation APIs do not provide timezone, so no timezone file is written. |
| **`--no-weather`** | **System local time** (weather is not run, so no location timezone is available). |
| **Weather on but no valid timezone** (e.g. weather failed, or timezone file missing/invalid) | **System local time** (fallback). |

Summary: **Timezone is used** only when (1) you set `TZ`, or (2) weather is enabled, you pass a **postal code** (or location that resolves to coordinates), and `weather.rb` successfully gets weather from Open-Meteo or NWS and writes a timezone. **ICAO/IATA (airport codes) use system local time** because METAR does not supply timezone. All other cases announce **system local time**.

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
