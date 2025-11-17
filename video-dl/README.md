# yt-dlp accessory script

basically abstracting away two commands to determine which set of videos i want, so all i have to do is enter a command and the url to get it kicked off

// formats available
yt-dlp -F "https://www.youtube.com/watch?v=-In1EPx9t8M"

// dl highest quality audio video
yt-dlp --continue --retries 10 --fragment-retries 10 --merge-output-format mp4 --no-check-certificate -f "234+270" -P "$HOME/Downloads" "https://www.youtube.com/watch?v=-In1EPx9t8M"