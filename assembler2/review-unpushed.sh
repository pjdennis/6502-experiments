#!/bin/bash
# Review unpushed commits with navigation

commits=($(git log @{u}..HEAD --reverse --format=%H))
total=${#commits[@]}

if [ "$total" -eq 0 ]; then
    echo "No unpushed commits."
    exit 0
fi

i=0
while true; do
    commit="${commits[$i]}"
    num=$((i + 1))
    clear
    echo "Commit $num of $total: (v to view, p for previous, n for next, q to quit)"
    echo
    git log --format="%h %s%n%n%b" -1 "$commit"

    read -rsn1 key
    case "$key" in
        v) git show --color=always "$commit" | less -R ; [ "$i" -lt $((total - 1)) ] && ((i++)) ;;
        p) [ "$i" -gt 0 ] && ((i--)) ;;
        n) [ "$i" -lt $((total - 1)) ] && ((i++)) ;;
        q) break ;;
    esac
done
