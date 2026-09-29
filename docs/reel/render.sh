#!/bin/zsh
# Render the reel, then add the music. Needs public/take.mp4 from record.sh.
set -e
DIR=${0:A:h}; cd $DIR
TRACK="music/Funky Chunk.mp3"
if [ ! -f "$TRACK" ]; then
  mkdir -p music
  curl -fsSL -o "$TRACK" "https://incompetech.com/music/royalty-free/mp3-royaltyfree/Funky%20Chunk.mp3"
fi
npx remotion render src/index.ts Reel out/reel.mp4 --codec=h264 --crf=18 --log=error
D=$(ffprobe -v error -show_entries format=duration -of csv=p=0 out/reel.mp4)
ffmpeg -hide_banner -loglevel error -y -i out/reel.mp4 -i "$TRACK" -filter_complex \
  "[1:a]atrim=0:$D,asetpts=PTS-STARTPTS,afade=t=out:st=$(echo "$D - 3" | bc):d=3,loudnorm=I=-14:TP=-1.5:LRA=11[a]" \
  -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 192k -ar 48000 -shortest -movflags +faststart out/omacchiato-reel.mp4
echo "$DIR/out/omacchiato-reel.mp4"
