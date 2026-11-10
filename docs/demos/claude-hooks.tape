Output docs/demos/claude-hooks.gif
Require jq
Set FontSize 14
Set Width 1000
Set Height 300
Set Padding 12
Set TypingSpeed 30ms
Set Framerate 12

Hide
Type "alias hook=docs/demos/claude-hooks.sh; clear"
Enter
Show

Type `hook 'git commit -m "updated the readme"'`
Enter
Wait+Screen@10s /and retry\./
Sleep 1s
Type `hook 'git commit -m "docs: README shows the hooks"'`
Enter
Wait+Screen@10s /allow/
Sleep 3s
Ctrl+L

Type `hook 'gh pr create --body "This PR updates things."'`
Enter
Wait+Screen@10s /retry/
Sleep 3s
Ctrl+L

Type `hook 'swaymsg exit'`
Enter
Wait+Screen@10s /unique/
Sleep 3s
Ctrl+L

Type `hook 'pytest tests/'`
Enter
Wait+Screen@10s /rewrite/
Sleep 3s
