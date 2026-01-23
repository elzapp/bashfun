#!/usr/bin/env bash

#
# Thanks to https://www.youtube.com/@yousuckatprogramming for a lot of the stuff done here
#

if ((BASH_VERSINFO[0] < 5)); then
    printf "Error: This script requires Bash version 5 or higher.\n"
    printf "Current version: %s\n" $BASH_VERSION
    exit 1
fi

BOARD_WIDTH=10
BOARD_HEIGHT=20

declare -a COLORS
COLORS[0]="  "                     # Empty
COLORS[1]="\033[41m  \033[0m"      # Red
COLORS[2]="\033[42m  \033[0m"      # Green
COLORS[3]="\033[43m  \033[0m"      # Yellow
COLORS[4]="\033[44m  \033[0m"      # Blue
COLORS[5]="\033[45m  \033[0m"      # Magenta
COLORS[6]="\033[46m  \033[0m"      # Cyan
COLORS[7]="\033[47m  \033[0m"      # White


POSITION="\033[%d;%dH"
HIDE_CURSOR="\033[?25l"
SHOW_CURSOR="\033[?25h"

pieces=(
    # I (cyan, color 6)
    "0000;6666;0000;0000|0600;0600;0600;0600"
    # O (yellow, color 3)
    "0330;0330;0000;0000"
    # T (magenta, color 5)
    "0500;5550;0000;0000|0500;0550;0500;0000|0000;5550;0500;0000|0500;5500;0500;0000"
    # S (green, color 2)
    "0220;2200;0000;0000|2000;2200;0200;0000"
    # Z (red, color 1)
    "1100;0110;0000;0000|0010;0110;0100;0000"
    # J (blue, color 4)
    "4000;4440;0000;0000|0440;0400;0400;0000|0000;4440;0040;0000|0400;0400;4400;0000"
    # L (white, color 7)
    "0070;7770;0000;0000|0700;0700;0770;0000|0000;7770;7000;0000|7700;0700;0700;0000"
)

declare -A board
for ((y=0; y<BOARD_HEIGHT; y++)); do
    for ((x=0; x<BOARD_WIDTH; x++)); do
        board[$x,$y]="0"
    done
done

current_piece=0
current_rotation=0
current_x=3
current_y=0

declare -a piece_bag
bag_index=7

score=0
lines_cleared=0

function setup_terminal() {
    stty -echo -icanon time 0 min 0
    printf $HIDE_CURSOR
    clear
}

function restore_terminal() {
    stty echo icanon
    printf $SHOW_CURSOR
    clear
}

trap restore_terminal EXIT

# Using a shuffle bag instead of pure random, to create the perception
# of a fairer randomness (Ensures that you don't get the same piece
# several times in a row)
# https://en.wikipedia.org/wiki/Fisher%E2%80%93Yates_shuffle#Python_implementation
function shuffle_bag() {
    piece_bag=(0 1 2 3 4 5 6)
    for ((i=6; i>0; i--)); do
        j=$((RANDOM % (i+1)))
        tmp=${piece_bag[$i]}
        piece_bag[$i]=${piece_bag[$j]}
        piece_bag[$j]=$tmp
    done
    bag_index=0
}

function spawn_new_piece() {
    if ((bag_index >= 7)); then
        shuffle_bag
    fi
    current_piece=${piece_bag[$bag_index]}
    bag_index=$((bag_index+1))
    current_rotation=0
    current_x=3
    current_y=0
    
    if ! can_move_piece 0 0; then
        return 1
    fi
    return 0
}

function get_bitmap() {
    local piece_idx=$1
    local rotation=$2
    local rotations="${pieces[$piece_idx]}"
    IFS='|' read -r -a rotation_arr <<< "$rotations"
    local num_rotations=${#rotation_arr[@]}
    local actual_rotation=$((rotation % num_rotations))
    printf "%s\n" "${rotation_arr[$actual_rotation]}"
}

function can_move_piece() {
    local dx=$1
    local dy=$2
    local rot=${3:-$current_rotation}
    
    local bitmap
    bitmap=$(get_bitmap $current_piece $rot)
    IFS=';' read -r -a rows <<< "$bitmap"
    
    for ((i=0; i<4; i++)); do
        local row="${rows[$i]}"
        for ((j=0; j<4; j++)); do
            local val=${row:$j:1}
            if [[ $val != "0" ]]; then
                local px=$((current_x + dx + j))
                local py=$((current_y + dy + i))
                
                if ((px < 0 || px >= BOARD_WIDTH || py >= BOARD_HEIGHT)); then
                    return 1 # outside the board
                fi
                
                if ((py >= 0)); then
                    if [[ ${board[$px,$py]} != "0" ]]; then
                        return 1 # other piece in the way
                    fi
                fi
            fi
        done
    done
    return 0
}

function draw_piece() {
    local bitmap
    bitmap=$(get_bitmap $current_piece $current_rotation)
    IFS=';' read -r -a rows <<< "$bitmap"
    
    for ((i=0; i<4; i++)); do
        local row="${rows[$i]}"
        for ((j=0; j<4; j++)); do
            local val=${row:$j:1}
            if [[ $val != "0" ]]; then
                local px=$((current_x + j))
                local py=$((current_y + i))
                if ((px >= 0 && px < BOARD_WIDTH && py >= 0 && py < BOARD_HEIGHT)); then
                    board[$px,$py]="$val"
                fi
            fi
        done
    done
}

function erase_piece() {
    local bitmap
    bitmap=$(get_bitmap $current_piece $current_rotation)
    IFS=';' read -r -a rows <<< "$bitmap"
    
    for ((i=0; i<4; i++)); do
        local row="${rows[$i]}"
        for ((j=0; j<4; j++)); do
            local val=${row:$j:1}
            if [[ $val != "0" ]]; then
                local px=$((current_x + j))
                local py=$((current_y + i))
                if ((px >= 0 && px < BOARD_WIDTH && py >= 0 && py < BOARD_HEIGHT)); then
                    board[$px,$py]="0"
                fi
            fi
        done
    done
}

function lock_piece() {
    draw_piece
    clear_lines
    if ! spawn_new_piece; then
        return 1
    fi
    return 0
}

function clear_lines() {
    local lines_to_clear=0
    
    for ((y=BOARD_HEIGHT-1; y>=0; y--)); do
        local full=1
        for ((x=0; x<BOARD_WIDTH; x++)); do
            if [[ ${board[$x,$y]} == "0" ]]; then
                full=0
                break
            fi
        done
        
        if ((full)); then
            ((lines_to_clear++))
            # Move all lines above down
            for ((yy=y; yy>0; yy--)); do
                for ((x=0; x<BOARD_WIDTH; x++)); do
                    board[$x,$yy]="${board[$x,$((yy-1))]}"
                done
            done
            # Clear top line
            for ((x=0; x<BOARD_WIDTH; x++)); do
                board[$x,0]="0"
            done
            ((y++))  # Check same line again
        fi
    done
    
    if ((lines_to_clear > 0)); then
        ((lines_cleared += lines_to_clear))
        case $lines_to_clear in
            1) ((score += 100)) ;;
            2) ((score += 300)) ;;
            3) ((score += 500)) ;;
            4) ((score += 800)) ;;
        esac
    fi
}

function move_piece() {
    local dx=$1
    local dy=$2
    
    if can_move_piece $dx $dy; then
        current_x=$((current_x + dx))
        current_y=$((current_y + dy))
        return 0
    fi
    return 1
}

function rotate_piece() {
    local new_rotation=$(((current_rotation + 1)))
    if can_move_piece 0 0 $new_rotation; then
        current_rotation=$new_rotation
        return 0
    fi
    if can_move_piece -1 0 $new_rotation; then
        current_x=$((current_x - 1))
        current_rotation=$new_rotation
        return 0
    fi
    if can_move_piece 1 0 $new_rotation; then
        current_x=$((current_x + 1))
        current_rotation=$new_rotation
        return 0
    fi
    return 1
}

function hard_drop() {
    while can_move_piece 0 1; do
        current_y=$((current_y + 1))
        ((score += 2))
    done
}

function render() {
    printf $POSITION 0 0  # Move cursor to top-left
    
    printf "╔════════════════════╗\n"
    for ((y=0; y<BOARD_HEIGHT; y++)); do
        printf "║"
        for ((x=0; x<BOARD_WIDTH; x++)); do
            local cell=${board[$x,$y]}
            printf "${COLORS[$cell]}"
        done
        printf "║\n"
    done
    printf "╚════════════════════╝\n\n"
    printf "  %7s %6d\n" "Score:" $score
    printf "  %7s %6d\n\n" "Lines:" $lines_cleared
    printf "  Controls:\n"
    printf "  %3s = %s\n" "A/D" "Move left/right" "W" "Rotate" "S" "Hard drop" "Q" "Quit" "P" "Pause"
}

function pause() {
    printf $POSITION 12 4
    printf "╔══════════════╗\n"
    printf $POSITION 13 4
    printf "║    PAUSE !   ║\n"
    printf $POSITION 14 4
    printf "╚══════════════╝\n"

    read -rsn1 _
}



function main() {
    setup_terminal
    shuffle_bag
    spawn_new_piece
    
    local last_drop=$(date +%s%N)
    local starting_drop_interval=1000000000
    local game_over=0
    
    draw_piece
    render
    
    while ((game_over == 0)); do
        local drop_interval=$(( starting_drop_interval - (score * 100000)  ))
        erase_piece
        
        local key=""
        read -rsn1 -t 0.05 key
        
        case "$key" in
            a|A) move_piece -1 0 ;;
            d|D) move_piece 1 0 ;;
            w|W) rotate_piece ;;
            s|S) 
                hard_drop
                if ! lock_piece; then
                    game_over=1
                fi
                last_drop=$(date +%s%N)
                ;;
            q|Q) game_over=1 ;;
            p|P) pause ;;
        esac
        
        local now=$(date +%s%N)
        if ((now - last_drop >= drop_interval)); then
            if ! move_piece 0 1; then
                if ! lock_piece; then
                    game_over=1
                fi
            fi
            last_drop=$now
        fi
        
        draw_piece
        render
    done
    
    printf $POSITION 12 4
    printf "╔══════════════╗\n"
    printf $POSITION 13 4
    printf "║  GAME OVER!  ║\n"
    printf $POSITION 14 4
    printf "╠══════════════╣\n"
    printf $POSITION 15 4
    printf "║ Score: %5d ║\n" $score
    printf $POSITION 16 4
    printf "╚══════════════╝\n"
    
    sleep 3
}

main
