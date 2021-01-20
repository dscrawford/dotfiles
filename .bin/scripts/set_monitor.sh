#!/bin/bash

xrandr --auto
xrandr --output DP-0 --left-of DP-2
xrandr --output DP-0 --primary
xrandr --output DP-2 --mode 3840x2160 --rate 60
xrandr --output DP-0 --mode 2560x1440 --rate 144
