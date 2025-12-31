# Makefile for saytime-weather-rb

.PHONY: build clean install package test

build:
	@echo "No build step needed - Ruby scripts are interpreted"

clean:
	rm -rf debian/saytime-weather-rb
	rm -rf debian/.debhelper
	rm -f debian/files
	rm -f debian/substvars
	rm -f debian/*.debhelper.log
	rm -f debian/*.substvars

install:
	@echo "Use 'dpkg-buildpackage' to create Debian package"

package:
	dpkg-buildpackage -us -uc -b

test:
	@echo "Running basic syntax checks..."
	ruby -c weather.rb
	ruby -c saytime.rb
	@echo "Syntax checks passed!"

.DEFAULT_GOAL := build

