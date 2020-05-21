#!/bin/sh

docker build -t inkmake-inkscape0.9 -f test/Dockerfile.0.9 .
docker build -t inkmake-inkscape1.0 -f test/Dockerfile.1.0 .

docker run --rm -i -v "$PWD:$PWD" -w "$PWD" -e RUBYLIB=lib --entrypoint=sh inkmake-inkscape1.0 -c "bin/inkmake -f -o test/out1.0 test/Inkfile"
docker run --rm -i -v "$PWD:$PWD" -w "$PWD" -e RUBYLIB=lib --entrypoint=sh inkmake-inkscape0.9 -c "bin/inkmake -f -o test/out0.9 test/Inkfile"
