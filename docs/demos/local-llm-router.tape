Output docs/demos/local-llm-router.gif
Set FontSize 15
Set Width 900
Set Height 420
Set Padding 12
Set TypingSpeed 40ms
Set Framerate 12

Type "ollama list"
Enter
Sleep 2s
Type "# draft a commit message for a diff — on the local GPU, zero hosted tokens"
Enter
Type "docs/demos/local-llm-router.sh"
Enter
# Match only the model's output (subject + separator), never the typed
# command line — "docs/demos/..." burned a looser pattern once already.
Wait+Screen@120s /(feat|fix|refactor|chore)[(:]/
Sleep 4s
