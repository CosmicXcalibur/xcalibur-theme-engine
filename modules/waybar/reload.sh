#!/usr/bin/env bash

waybar_reload() {

    pkill waybar

    waybar >/dev/null 2>&1 &

}
