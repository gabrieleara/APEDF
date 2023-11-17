#!/bin/bash

function telegram_notify() {
    local arg
    local val
    local bot_token="$TELEGRAM_DEFAULT_BOT_TOKEN"
    local chatid="$TELEGRAM_DEFAULT_CHATID"
    local parse_mode=""
    local text=""

    while [ "$#" != 0 ]; do
        arg="$1"

        val="$(echo "$arg" | grep -e '^chatid=' | sed 's/chatid=//')"
        if [ -n "$val" ]; then
            chatid="$val"
            shift
            continue
        fi

        val="$(echo "$arg" | grep -e '^bot=' | sed 's/bot=//')"
        if [ -n "$val" ]; then
            bot_token="$val"
            shift
            continue
        fi

        val="$(echo "$arg" | grep -e '^parse_mode=' | sed 's/parse_mode=//')"
        if [ -n "$val" ]; then
            parse_mode="$val"
            shift
            continue
        fi

        text="$arg"
        shift
    done

    curl -s "https://api.telegram.org/bot${bot_token}/sendMessage?parse_mode=${parse_mode}&chat_id=${chatid}&text=${text}" >/dev/null
}
