# The video tour

This folder makes the one-minute tour that the main README links to
(https://youtu.be/QfTOFTOCD-w). An agent recorded and edited it on a real
Mac: `demo.sh` drives the desktop through the command-line tools, and
[Remotion](https://www.remotion.dev) turns the recording into the reel.

## Make it again

1. Turn on Do Not Disturb. A notification in the recording goes public
   with it.
2. Run `./record.sh`. It sets `demo = on` in `bar-pills.conf`, so the
   popups show sample data, records `demo.sh` on workspace 5 for about
   75 seconds, and then puts the desktop back. Do not touch the Mac while
   it runs.
3. Compare the times that it prints with the times in `src/Reel.tsx`.
   Each popup, theme and segment there starts at a time in the take. If a
   step moved, change the time.
4. Run `npm install`, then `npm run render`. The result is
   `out/omacchiato-reel.mp4`. Run `npm run studio` to scrub through the
   reel in a browser while you change it.

The camera pushes in on each popup at the frame that `onPopup` computes
from the popup's box in the footage. If a popup moves, find its new box
in a frame of `public/take.mp4` and change `r` in `popups`.

## Music

"Funky Chunk" by Kevin MacLeod (incompetech.com), licensed under
Creative Commons: By Attribution 4.0
(https://creativecommons.org/licenses/by/4.0/). `render.sh` downloads it.
A video that uses it must carry that credit.

## Licenses

Remotion is free for individuals and for companies of up to three
people. A larger company needs a Remotion company license to render.
