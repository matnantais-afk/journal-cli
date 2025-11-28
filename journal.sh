#!/bin/zsh

# ===== PATHS =====
PLAINTEXT_JOURNAL="$HOME/journal-cli/journal.txt"           # old plain file (for import)
ENCRYPTED_JOURNAL="$HOME/journal-cli/journal.enc"           # encrypted journal file
JOURNAL_FILE="$HOME/journal-cli/journal_decrypted.tmp"      # temp decrypted file
MARKDOWN_FILE="$HOME/journal-cli/journal.md"

# ===== COLORS =====
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RED="\033[31m"
MAGENTA="\033[35m"
RESET="\033[0m"

JOURNAL_PASSWORD=""

print_banner() {
  echo
  echo "${MAGENTA}=========================================${RESET}"
  echo "${CYAN}        JOURNAL CLI  (encrypted)         ${RESET}"
  echo "${MAGENTA}=========================================${RESET}"
  echo
}

decrypt_journal() {
  # If encrypted file exists, try to decrypt it
  if [ -f "$ENCRYPTED_JOURNAL" ]; then
    if ! openssl enc -aes-256-cbc -d -pbkdf2 \
      -in "$ENCRYPTED_JOURNAL" \
      -out "$JOURNAL_FILE" \
      -pass pass:"$JOURNAL_PASSWORD" 2>/dev/null; then
      echo "${RED}❌ Wrong password. Try again.${RESET}"
      return 1
    fi
  else
    # No encrypted file yet: import old plaintext or start fresh
    if [ -f "$PLAINTEXT_JOURNAL" ]; then
      cp "$PLAINTEXT_JOURNAL" "$JOURNAL_FILE"
      echo "${YELLOW}Imported existing plaintext journal and will encrypt it.${RESET}"
    else
      : > "$JOURNAL_FILE"
      echo "${YELLOW}No existing journal found. Starting a new one.${RESET}"
    fi
  fi
  return 0
}

encrypt_journal() {
  # If temp decrypted file exists, encrypt it
  if [ -f "$JOURNAL_FILE" ]; then
    openssl enc -aes-256-cbc -pbkdf2 -salt \
      -in "$JOURNAL_FILE" \
      -out "$ENCRYPTED_JOURNAL" \
      -pass pass:"$JOURNAL_PASSWORD" 2>/dev/null
  fi
}

secure_cleanup() {
  encrypt_journal
  rm -f "$JOURNAL_FILE"
}

new_entry() {
  local timestamp mood note line tags

  timestamp=$(date +"%Y-%m-%d %H:%M:%S")

  # Ask for mood and validate input (1–10)
  while true; do
    echo
    echo "${YELLOW}How's your mood today from 1 to 10?${RESET}"
    read mood

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
  echo "${GREEN}✅ Entry saved.${RESET}"
}

view_history() {
  echo
  echo "${CYAN}📘 Journal history:${RESET}"
  echo

  if [ -s "$JOURNAL_FILE" ]; then
    cat "$JOURNAL_FILE"
  else
    echo "${RED}No journal entries yet.${RESET}"
  fi
}

search_entries() {
  echo
  echo "${YELLOW}Enter a keyword to search in your entries:${RESET}"
  read keyword

  if [ ! -s "$JOURNAL_FILE" ]; then
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
  if [ ! -s "$JOURNAL_FILE" ]; then
    echo
    echo "${RED}No journal entries yet.${RESET}"
    return
  fi

  local count=0
  local sum=0
  local min=""
  local max=""

  while read -r label value _; do
    if [ "$label" != "Mood:" ]; then
      continue
    fi
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
  if [ ! -s "$JOURNAL_FILE" ]; then
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

  awk -v d="$target_date" '
    /^----- / {
      if (entry != "") {
        if (keep) print entry "\n"
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
      if (entry != "" && keep) print entry
    }
  ' "$JOURNAL_FILE"

  if ! grep -q "$target_date" "$JOURNAL_FILE"; then
    echo "${RED}No entries found for that date.${RESET}"
  fi
}

filter_by_tag() {
  if [ ! -s "$JOURNAL_FILE" ]; then
    echo
    echo "${RED}No journal entries yet.${RESET}"
    return
  fi

  echo
  echo "${YELLOW}Enter a tag to filter (you can type 'gym' or '#gym'):${RESET}"
  read tag

  tag=${tag#\#}

  echo
  echo "${CYAN}🏷️  Entries with tag #${tag}:${RESET}"
  echo

  grep -i -n -C 3 -- "Tags:.*#${tag}\b" "$JOURNAL_FILE" || {
    echo "${RED}No entries found with that tag.${RESET}"
  }
}

export_markdown() {
  if [ ! -s "$JOURNAL_FILE" ]; then
    echo
    echo "${RED}No journal entries yet.${RESET}"
    return
  fi

  {
    echo "# Journal Export"
    echo
    awk '
      /^----- / {
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

main_menu() {
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
        echo "${GREEN}🔒 Encrypting and exiting. Goodbye!${RESET}"
        break
        ;;
      *)
        echo "${RED}Invalid choice. Please try again.${RESET}"
        ;;
    esac
  done
}

# ===== STARTUP FLOW =====

print_banner

# Ask for password and decrypt journal (or init new one)
while true; do
  echo "${YELLOW}Enter your journal password (this protects your entries):${RESET}"
  read -s JOURNAL_PASSWORD
  echo

  if [ -z "$JOURNAL_PASSWORD" ]; then
    echo "${RED}Password cannot be empty.${RESET}"
    continue
  fi

  if decrypt_journal; then
    break
  fi
done

trap secure_cleanup EXIT

main_menu
