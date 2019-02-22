#!/usr/bin/env bash

set -u
set -e

LC_NUMERIC=C

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

bat_view_tmpl=$(get_tmux_option "@sysstat_bat_view_tmpl" 'BAT:#[fg=#{bat.color}]#{bat.pused}#[default]')

bat_medium_threshold=$(get_tmux_option "@sysstat_bat_medium_threshold" "45")
bat_low_threshold=$(get_tmux_option "@sysstat_bat_low_threshold" "15")

bat_color_high=$(get_tmux_option "@sysstat_bat_color_high" "green")
bat_color_medium=$(get_tmux_option "@sysstat_bat_color_medium" "yellow")
bat_color_low=$(get_tmux_option "@sysstat_bat_color_low" "red")

linux_get_bat() {
    echo $(($BAT_TOTAL / $BAT_COUNT))
}

openbsd_get_bat() {
    bf=$(sysctl -n hw.sensors.acpibat0.amphour0 | cut -d ' ' -f 1)
    bn=$(sysctl -n hw.sensors.acpibat0.amphour3 | cut -d ' ' -f 1)
    echo "(($bn * 100) / $bf)" | bc -l | awk -F '.' '{ print $1 }'
}

freebsd_get_bat() {
    sysctl -n hw.acpi.battery.life
}

battery_status() {
    case $(uname -s) in
    "Linux")
        BATTERIES=$(ls /sys/class/power_supply | grep BAT)
        BAT_COUNT=$(ls /sys/class/power_supply | grep BAT | wc -l)
        for BATTERY in $BATTERIES; do
            BAT_PATH=/sys/class/power_supply/$BATTERY
            STATUS=$BAT_PATH/status
            if [ -f "$BAT_PATH/energy_full" ]; then
                naming="energy"
            elif [ -f "$BAT_PATH/charge_full" ]; then
                naming="charge"
            elif [ -f "$BAT_PATH/capacity" ]; then
                cat "$BAT_PATH/capacity"
                return 0
            fi
            BAT_PERCENT=$((100 * $(cat $BAT_PATH/${naming}_now) / $(cat $BAT_PATH/${naming}_full)))
            BAT_TOTAL=$((${BAT_TOTAL-0} + $BAT_PERCENT))
        done
        linux_get_bat
        ;;
    "FreeBSD")
        STATUS=$(sysctl -n hw.acpi.battery.state)
        case $1 in
        "Discharging")
            if [ $STATUS -eq 1 ]; then
                freebsd_get_bat
            fi
            ;;
        "Charging")
            if [ $STATUS -eq 2 ]; then
                freebsd_get_bat
            fi
            ;;
        "")
            freebsd_get_bat
            ;;
        esac
        ;;
    "OpenBSD")
        openbsd_get_bat
        ;;
    "Darwin")
        case $1 in
        "Discharging")
            ext="No"
            ;;
        "Charging")
            ext="Yes"
            ;;
        esac

        ioreg -c AppleSmartBattery -w0 |
            grep -o '"[^"]*" = [^ ]*' |
            sed -e 's/= //g' -e 's/"//g' |
            sort |
            while read key value; do
                case $key in
                "MaxCapacity")
                    export maxcap=$value
                    ;;
                "CurrentCapacity")
                    export curcap=$value
                    ;;
                "ExternalConnected")
                    if [ -n "$ext" ] && [ "$ext" != "$value" ]; then
                        exit
                    fi
                    ;;
                "FullyCharged")
                    if [ "$value" = "Yes" ]; then
                        exit
                    fi
                    ;;
                esac
                if [[ -n "$maxcap" && -n $curcap ]]; then
                    echo $((100 * $curcap / $maxcap))
                    break
                fi
            done
        ;;
    esac
}

get_bat_color() {
    local bat_pused=$1

    if fcomp "$bat_pused" "$bat_low_threshold"; then
        echo "$bat_color_low"
    elif fcomp "$bat_pused" "$bat_medium_threshold"; then
        echo "$bat_color_medium"
    else
        echo "$bat_color_high"
    fi
}

print_bat() {
    local bat_pused=$(battery_status)
    local bat_color=$(get_bat_color "$bat_pused")

    local bat_view="$bat_view_tmpl"
    bat_view="${bat_view//'#{bat.pused}'/$(printf "%.1f%%" "$bat_pused")}"
    bat_view="${bat_view//'#{bat.color}'/$(echo "$bat_color" | awk '{ print $1 }')}"
    bat_view="${bat_view//'#{bat.color2}'/$(echo "$bat_color" | awk '{ print $2 }')}"
    bat_view="${bat_view//'#{bat.color3}'/$(echo "$bat_color" | awk '{ print $3 }')}"

    echo "$bat_view"
}

main() {
    print_bat
}

main
