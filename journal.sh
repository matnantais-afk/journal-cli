#!/bin/zsh

JOURNAL_FILE="$HOME/journal-cli/journal.txt"
MARKDOWN_FILE="$HOME/journal-cli/journal.md"

# Colors
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RED="\033[31m"
RESET="\033[0m"

new_entry() {
  local timestamp mood note line tags

  timestamp=$(date +"%Y-%m-%d %H:%M:%S")

  # Ask for mood and validate input (1–10)
  while true; do
    echo
    echo "${YELLOW}How's your mood today from 1 to 10?${RESET}"
    read mood

    # Check: integer between 1 and 10
    if echo "$mood" | grep -Eq '^[0-9]+$' && [ "$mood" -ge 1 ] && [ "$mood" -le 10 ]; then
      break
    fi

    echo "${RED}Please enter a number from 1 to 10.${RESET}"
  done

  echo
  echo "${YELLOW}Add tags for this entry (optional, e.g.: #gym #work #focus).${RESET}"
  echo "${YELLOW}Press ENTER to skip tags.${RESET}"
  read tags

  echo
  echo "${YELLOW}Write a short note about your day.${RESET}"
  echo "${YELLOW}(Press ENTER on an empty line to finish.)${RESET}"

  note=""
  while true; do
    read -r line
    [ -z "$line" ] && break
    note+="$line\n"
  done

  {
    echo "----- $timestamp -----"
    echo "Mood: $mood"
    if [ -n "$tags" ]; then
      echo "Tags: $tags"
    fi
    printf "Note:\n%s\n" "$note"
    echo
  } >> "$JOURNAL_FILE"

  echo
  echo "${GREEN}✅ Entry saved to $JOURNAL_FILE${RESET}"
}

view_history() {
  echo
  echo "${CYAN}📘 Journal history:${RESET}"
  echo

  if [ -f "$JOURNAL_FILE" ]; then
    cat "$JOURNAL_FILE"
  else
    echo "${RED}No journal entries yet.${RESET}"
  fi
}

search_entries() {
  echo
  echo "${YELLOW}Enter a keyword to search in your entries:${RESET}"
  read keyword

  if [ ! -f "$JOURNAL_FILE" ]; then
    echo
    echo "${RED}No journal entries yet.${RESET}"
    return
  fi

  echo
  echo "${CYAN}🔍 Results for '${keyword}':${RESET}"
  echo

  grep -i -n -C 2 -- "$keyword" "$JOURNAL_FILE" || {
    echo "${RED}No matches found.${RESET}"
  }
}

show_stats() {
  if [ ! -f "$JOURNAL_FILE" ]; then
    echo
    echo "${RED}No journal entries yet.${RESET}"
    return
  fi

  local count=0
  local sum=0
  local min=""
  local max=""

  # Read all lines like "Mood: 7"
  while read -r label value _; do
    if [ "$label" != "Mood:" ]; then
      continue
    fi

    # only accept integers
    if ! echo "$value" | grep -Eq '^[0-9]+$'; then
      continue
    fi

    local mood=$value

    count=$((count + 1))
    sum=$((sum + mood))

    if [ -z "$min" ] || [ "$mood" -lt "$min" ]; then
      min=$mood
    fi

    if [ -z "$max" ] || [ "$mood" -gt "$max" ]; then
      max=$mood
    fi
  done < <(grep "^Mood:" "$JOURNAL_FILE")

  if [ "$count" -eq 0 ]; then
    echo
    echo "${RED}No mood data found in journal.${RESET}"
    return
  fi

  # floating point average
  local avg
  avg=$(awk -v s="$sum" -v c="$count" 'BEGIN { printf "%.2f", s / c }')

  echo
  echo "${CYAN}📊 Journal Stats:${RESET}"
  echo "Total entries: $count"
  echo "Average mood: $avg"
  echo "Best mood:    $max"
  echo "Worst mood:   $min"
}

filter_by_date() {
  if [ ! -f "$JOURNAL_FILE" ]; then
    echo
    echo "${RED}No journal entries yet.${RESET}"
    return
  fi

  echo
  echo "${YELLOW}Enter a date to filter (format: YYYY-MM-DD):${RESET}"
  read target_date

  echo
  echo "${CYAN}📅 Entries for ${target_date}:${RESET}"
  echo

  # Print full entries whose header date matches target_date
  awk -v d="$target_date" '
    /^----- / {
      if (entry != "") {
        # print previous entry if it matched
        if (keep) {
          print entry "\n"
        }
      }
      entry = $0 "\n"
      date = $2
      keep = (substr(date, 1, 10) == d)
      next
    }
    {
      entry = entry $0 "\n"
    }
    END {
      if (entry != "" && keep) {
        print entry
      }
    }
  ' "$JOURNAL_FILE"

  if ! grep -q "$target_date" "$JOURNAL_FILE"; then
    echo "${RED}No entries found for that date.${RESET}"
  fi
}

filter_by_tag() {
  if [ ! -f "$JOURNAL_FILE" ]; then
    echo
    echo "${RED}No journal entries yet.${RESET}"
    return
  fi

  echo
  echo "${YELLOW}Enter a tag to filter (you can type 'gym' or '#gym'):${RESET}"
  read tag

  # normalize: remove leading #
  tag=${tag#\#}

  echo
  echo "${CYAN}🏷️  Entries with tag #${tag}:${RESET}"
  echo

  grep -i -n -C 3 -- "Tags:.*#${tag}\b" "$JOURNAL_FILE" || {
    echo "${RED}No entries found with that tag.${RESET}"
  }
}

export_markdown() {
  if [ ! -f "$JOURNAL_FILE" ]; then
    echo
    echo "${RED}No journal entries yet.${RESET}"
    return
  fi

  {
    echo "# Journal Export"
    echo
    awk '
      /^----- / {
        # header -> markdown heading
        gsub(/^-+ /, "")
        gsub(/ -+$/, "")
        print "### " $0 "\n"
        next
      }
      /^Mood:/ {
        print "- " $0
        next
      }
      /^Tags:/ {
        print "- " $0
        next
      }
      /^Note:/ {
        print $0
        next
      }
      /^$/ {
        print
        next
      }
      {
        print "  " $0
      }
    ' "$JOURNAL_FILE"
  } > "$MARKDOWN_FILE"

  echo
  echo "${GREEN}✅ Exported to $MARKDOWN_FILE${RESET}"
}

while true; do
  echo
  echo "${CYAN}===== JOURNAL MENU =====${RESET}"
  echo "1) New entry"
  echo "2) View history"
  echo "3) Search entries"
  echo "4) View stats"
  echo "5) Filter by date"
  echo "6) Filter by tag"
  echo "7) Export to Markdown"
  echo "8) Quit"
  echo
  echo -n "Choose an option (1-8): "
  read choice

  case "$choice" in
    1) new_entry ;;
    2) view_history ;;
    3) search_entries ;;
    4) show_stats ;;
    5) filter_by_date ;;
    6) filter_by_tag ;;
    7) export_markdown ;;
    8)
      echo
      echo "${GREEN}👋 Goodbye!${RESET}"
      break
      ;;
    *)
      echo "${RED}Invalid choice. Please try again.${RESET}"
      ;;
  esac
done
