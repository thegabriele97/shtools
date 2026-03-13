#!/bin/bash

# launcher.sh — entrypoint for curl | bash usage
#
# usage:
#   curl -sL https://sh.t | bash
#   curl -sL https://sh.t | bash -s -- compress-video /in /out h265
#
# why not just pipe tools.sh directly?
#   when piped, bash reads the script from stdin — leaving no stdin
#   available for user interaction (fzf, read prompts).
#   this launcher downloads tools.sh to /tmp first, then re-execs it
#   with </dev/tty to restore stdin from the terminal.

# to demo locally:
#   cat tools.sh | bash          ← read won't work (not asking for arguments)
#   cat launcher.sh | bash       ← everything works correctly

# download tools.sh to /tmp (volatile, disappears on reboot)
curl -sL https://raw.githubusercontent.com/thegabriele97/shtools/main/tools.sh -o /tmp/tools.sh

# exec replaces this process with bash running tools.sh
# </dev/tty restores stdin from the terminal so fzf and read work correctly
# "$@" forwards any arguments passed to the launcher (e.g. compress-video /in /out)
exec bash /tmp/tools.sh "$@" </dev/tty