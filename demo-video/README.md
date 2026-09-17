# Demo recorder

`demo.cpp` drives the real QtPass widgets (linked against `libqtpass.a` of a
checkout) under the `offscreen` platform, grabs every top-level window twelve
times a second, composites them with a drawn cursor and writes PNG frames.
Everything runs against a scripted `gpg` in `/tmp/qtpass-demo`, no real keys or
stores are touched.

```sh
# point INCLUDEPATH/LIBS/RESOURCES in demo.pro at a built QtPass tree, then
qmake6 && make
for clip in wizard addpassword menubar profiles; do
  QT_QPA_PLATFORM=offscreen ./demo $clip frames-$clip
  ffmpeg -framerate 12 -i frames-$clip/frame%05d.png -c:v libx264 -pix_fmt yuv420p \
    -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" $clip.mp4
done
```

GIFs: `ffmpeg -i clip.mp4 -vf "fps=10,scale=800:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=3" clip.gif`
