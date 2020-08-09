#!/bin/sh

if ! screen -list | grep -q adafruit_usb_serial; then
  ./upload_connect.sh
fi

screen -S adafruit_usb_serial -p 0 -X readreg p "$(cd "$(dirname "$1")"; pwd -P)/$(basename "$1")"
screen -S adafruit_usb_serial -p 0 -X paste p
cksum -o 1 $1 | sed -n 's/\(^[0-9]*\) .*/obase=16; \1/p' | bc

