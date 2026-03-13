Output demo.gif

Set FontSize 12
Set Width 1550
Set Height 700
Set Theme "Catppuccin Mocha"
#Set FontFamily "JetBrains Mono"
Set TypingSpeed 75ms
# Set Padding 20

Hide
Type "alias tools='curl -Ls https://raw.githubusercontent.com/thegabriele97/shtools/main/launcher.sh | bash -s --'"
Enter
Sleep 500ms
Type "clear"
Enter
Sleep 500ms
Show

# Avvia il tool
Type "tools"
Enter
Sleep 2s

# Naviga nella TUI fzf (frecce su/giù)
Down
Sleep 600ms
Down
Sleep 600ms
Type "fnd-ha"
Sleep 1s

# Seleziona uno script
Enter
Sleep 1.2s

# Inserisce i parametri richiesti
Type "/tmp/test/a"
Sleep 400ms
Enter
Sleep 400ms
Type "/tmp/test/b"
Sleep 400ms
Enter
Type "png,txt"
Sleep 600ms
Enter
Sleep 3s
