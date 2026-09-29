#!/bin/zsh
# Record one take of demo.sh on workspace 5, then put the desktop back.
# Writes out/take.mov, out/marks.txt and public/take.mp4 (the footage the
# reel reads). Change nothing on screen while it runs, about 75 seconds.
DIR=${0:A:h}; B=~/.local/bin
CONF=~/.config/omacchiato/bar-pills.conf
mkdir -p $DIR/out $DIR/public
before=($(pgrep -x ghostty))

grep -q '^demo = on' $CONF || printf 'demo = on\n' >> $CONF
$B/omacchiato-omni slot 5 >/dev/null 2>&1; sleep 1.5

start=$(perl -MTime::HiRes=time -e 'printf "%.2f", time')
screencapture -x -v -V 100 $DIR/out/take.mov & CAP=$!
sleep 1
$DIR/demo.sh $DIR/out/marks-abs.txt
kill -INT $CAP; wait $CAP

# Clean up: only the Ghostty processes this take started.
for pid in $(pgrep -x ghostty); do (( ${before[(Ie)$pid]} )) || kill $pid; done
sed -i '' '/^demo = on$/d' $CONF
$B/theme-set "light:catppuccin-latte,dark:catppuccin" >/dev/null 2>&1
$B/omacchiato-omni slot 4 >/dev/null 2>&1

# Seconds into the take, which is what the times in src/Reel.tsx are.
awk -F'|' -v s=$start '{printf "%.2f|%s|%s\n", $1 - s, $2, $3}' $DIR/out/marks-abs.txt > $DIR/out/marks.txt
ffmpeg -hide_banner -loglevel error -y -i $DIR/out/take.mov -t 72 -vf "fps=60,scale=1920:-2:flags=lanczos" \
  -c:v libx264 -crf 16 -preset fast -pix_fmt yuv420p -g 30 $DIR/public/take.mp4
cat $DIR/out/marks.txt
