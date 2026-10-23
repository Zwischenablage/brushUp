.PHONY: build run test app install clean

build:
	swift build

run:
	swift run Pelican

test:
	swift test

app:
	./scripts/build-app.sh

install:
	./scripts/build-app.sh --install

clean:
	rm -rf .build build
