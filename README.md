# Saytime Weather (Ruby Version)

![GitHub total downloads](https://img.shields.io/github/downloads/hardenedpenguin/saytime_weather_rb/total?style=flat-square)

A Ruby implementation of a time and weather announcement system for Asterisk PBX, designed for radio systems, repeater controllers, and amateur radio applications. Complete rewrite in Ruby with zero external dependencies.

> **⚠️ WARNING:** Do not install this package alongside any other version of saytime_weather. This Ruby implementation is a complete replacement and conflicts with other implementations. Please uninstall any existing saytime_weather packages before installing this one.

## Requirements

- Ruby 2.7+
- Asterisk PBX (tested with versions 16+)
- Internet connection for weather API access
- **gpsd** (optional, recommended for `--gps` / `location_source = gps`; Debian package `Recommends: gpsd`)

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
| `SAYTIME_FILE_OWNER` | When running as root, `-s 1` / `-s 2` save output is `chown`ed to this user (default `asterisk`) |

Cron and DTMF (`*C1`) normally use default **silent=0** (play only). Scratch files are removed after each run so a root cron job does not leave root-owned `/tmp` files that block the `asterisk` user. Use **`-s 1`** or **`-s 2`** only when you intentionally want `/tmp/current-time.ulaw` kept.
| `WEATHER_CONFIG` | Path to `weather.ini` (default `/etc/asterisk/local/weather.ini`) |
| `WEATHERAPI_KEY` | WeatherAPI.com key when `weather_provider = weatherapi` (overrides ini if `weatherapi_key` is unset) |
| `SAYTIME_SOUND_ROOT` | Base Asterisk English sounds directory (default `/usr/share/asterisk/sounds/en`) |
| `ASTERISK_BIN` | Asterisk binary for playback (default `/usr/sbin/asterisk`) |

Optional **`weather.ini`** keys under `[weather]` (see the commented template at `/usr/share/saytime-weather-rb/weather.ini`):

| Area | Keys |
|------|------|
| **Providers** | `weather_provider` (optional), `weather_provider_random`, `weather_provider_random_max_attempts`, `http_probe_timeout`, `weatherapi_key` |
| **Location** | `location_source` (`postal` or `gps`), `gpsd_host`, `gpsd_port`, `gps_min_mode`, `gps_max_age_seconds`, `gps_fallback_location`, … |
| **Performance** | `geocode_cache_max_age_seconds`, `timezone_cache_max_age_seconds`, `saytime_play_delay` |
| **HTTP / airports** | `http_timeout_short`, `http_timeout_long`, `nominatim_delay`, `http_get_retries`, `http_get_retry_sleep`, `airports_cache_max_age_seconds`, `airports_data_url` |

Environment variable **`SAYTIME_PLAY_DELAY`** overrides `saytime_play_delay` when set.

## Installation

```bash
cd /tmp
wget https://github.com/hardenedpenguin/saytime_weather_rb/releases/download/v0.0.30/saytime-weather-rb_0.0.30-1_all.deb
sudo apt install ./saytime-weather-rb_0.0.30-1_all.deb
```

Or install the latest `.deb` from [Releases](https://github.com/hardenedpenguin/saytime_weather_rb/releases).

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
weather_provider_random = YES
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
- **default_country**: ISO country code for postal code lookups (default: `us`). Override per run with `-d` / `--default-country` on `weather.rb` or `saytime.rb` without editing `weather.ini`. Applies to **5-digit** postcodes (e.g. `-d fr -l 75001` → Paris) and **4-digit** postcodes when the country is not `us` (e.g. `-d au -l 2000` → Sydney).
- **weather_provider** (optional; internal fallback `openmeteo` when unset):
  - `openmeteo`: worldwide, no API key
  - `nws`: US-only, no API key (falls back to `openmeteo` if unavailable / non-US)
  - `metno`: worldwide, no API key (MET Norway / Yr)
  - `wttr`: worldwide, no API key (wttr.in)
  - `7timer`: worldwide, no API key (7Timer!)
  - `weatherapi`: worldwide; requires `weatherapi_key` in `weather.ini` or `WEATHERAPI_KEY` in the environment. When selected, postal codes and airport codes are sent directly to WeatherAPI (skips Nominatim geocoding and METAR).
- **weatherapi_key**: API key for WeatherAPI.com (required when `weather_provider = weatherapi`). Also accepted as `WEATHERAPI_KEY`.
- **weather_provider_random** (default: `YES`): spread postal-code lookups across eligible providers; Open-Meteo (or your `weather_provider` if set) is tried last. `weatherapi` joins the rotation only when a key is configured. Set `NO` and set `weather_provider` to pin a single provider. Does not affect airport METAR lookups unless `weather_provider = weatherapi`.

### Additional Weather Data

The following options control display of additional weather information. Units are automatically selected based on `Temperature_mode`.

For **postal codes**, data comes from your configured weather provider. For **airport codes (IATA/ICAO)**, temperature and condition come from METAR; when any `show_*` option is `YES`, supplemental fields and timezone are filled from Open-Meteo using coordinates from the Our Airports database (when available).

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
sudo /usr/sbin/weather.rb --default-country fr 75001  # France (5-digit)
sudo /usr/sbin/weather.rb --default-country au 2000  # Australia (4-digit, Sydney CBD)
sudo /usr/sbin/weather.rb 48.8566,2.3522 v         # lat,lon coordinates
sudo /usr/sbin/weather.rb --gps v                  # GPS via gpsd (no location arg)
sudo /usr/sbin/weather.rb 75001 v                  # Display text only (verbose mode)
```

Options: `-d, --default-country CC`, `-c, --config FILE`, `-t, --temperature-mode M`, `--no-condition`, `--gps`, `-v, --verbose`, `-h, --help`

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
sudo /usr/sbin/saytime.rb --gps -n 123456          # GPS location via gpsd
sudo /usr/sbin/saytime.rb -l 48.8566,2.3522 -n 123456  # Explicit coordinates
TZ=UTC /usr/sbin/saytime.rb -l 75001 -n 123456 --no-weather  # UTC time
```

Required: `-n, --node_number=NUM`. `-l, --location_id=ID` is required when weather is enabled unless GPS is used.

Common options: `-u, --use_24hour`, `-d, --default-country CC`, `-c, --config FILE`, `--gps`, `-v, --verbose`, `--dry-run`, `--no-weather`, `--weather-subprocess`

### GPS location

Set `location_source = gps` in `weather.ini`, or pass `--gps` on the command line. Coordinates come from **gpsd** (recommended; package `Recommends: gpsd`). If gpsd is unavailable, the app tries `gpspipe` when installed. The last good fix is cached under `/tmp/saytime-gps-fix.json`.

**GPS setup script:** For a guided install of gpsd (shared on `127.0.0.1:2947` for saytime and other clients) plus Asterisk APRS/`app_gps` wiring, use [setup-asl3-gps.rb](https://github.com/hardenedpenguin/asl-misc-scripts/blob/main/setup-asl3-gps.rb) from [hardenedpenguin/asl-misc-scripts](https://github.com/hardenedpenguin/asl-misc-scripts):

```bash
curl -sSL https://raw.githubusercontent.com/hardenedpenguin/asl-misc-scripts/refs/heads/main/setup-asl3-gps.rb | sudo ruby
```

Run as root; the script prompts for callsign, USB device, and APRS options. After it finishes, use `--gps` or `location_source = gps` as below.

**Manual setup:**

```bash
sudo apt install gpsd gpsd-clients
# Configure /etc/default/gpsd for your USB serial device, then:
sudo systemctl enable --now gpsd
gpspipe -w -n 5   # verify fix

sudo /usr/sbin/saytime.rb --gps -n 123456
```

Optional `weather.ini` keys: `gpsd_host`, `gpsd_port`, `gps_min_mode`, `gps_max_age_seconds`, `gps_fallback_location` (postal code used when no fix). An explicit `-l` on the command line overrides `location_source = gps`.

**Important:** The `-l, --location_id` option is a `saytime.rb` option (not a `weather.rb` option). When you specify `-l <location>`, `saytime.rb` runs weather retrieval **in-process** by default (faster than spawning `weather.rb`). Use `--weather-subprocess` for the legacy subprocess behavior. Options `-d`, `-c`, `-v`, and settings from `weather.ini` are passed through automatically. You cannot use `-l` directly with `weather.rb` — it only accepts location as a positional argument.

**Programmatic API:** `SaytimeWeather.run_weather(location, verbose: true, use_gps: true, default_country: 'us')` returns `true`/`false` (see `lib/saytime_weather/weather_runner.rb`). Pass `use_gps: true` with a nil/empty location for GPS mode.

**12-hour format:** Times like 2:06 are announced as "two oh six" using `letters/o.ulaw` when present, otherwise the digit zero is used.

### When the announced time is in a timezone vs system local time

| Situation | What time is announced |
|-----------|------------------------|
| **`TZ` is set** (e.g. `TZ=UTC`) | Time in that zone; overrides location timezone from weather/GPS. |
| **Weather on**, `TZ` unset, location timezone file written | Time in the **location’s timezone** (postal, coordinates, GPS, or airport). |
| **Weather on, location = ICAO or IATA** (e.g. KDFW, JFK), `TZ` unset | **Airport timezone** when Our Airports has coordinates; otherwise **system local time**. |
| **`--no-weather`**, `TZ` unset | **System local time**. |
| **Weather on but no valid timezone**, `TZ` unset | **System local time**. |

Summary: set `TZ` when you want UTC or another zone regardless of GPS/weather location. Leave `TZ` unset to announce time in the weather location’s timezone.

Run with `--help` for complete option list.

## Asterisk Dialplan

```ini
[time_weather]
exten => s,1,NoOp(Time and Weather Announcement)
same => n,Set(NODENUM=${EXTEN})
same => n,System(/usr/sbin/saytime.rb -l 75001 -n ${NODENUM})
same => n,Hangup()
```

For GPS-based sites (with gpsd running):

```ini
same => n,System(/usr/sbin/saytime.rb --gps -n ${NODENUM})
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
