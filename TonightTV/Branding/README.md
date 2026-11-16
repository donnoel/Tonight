# Top-shelf artwork

`TopShelfPanorama.png` is the editable source raster for the static tvOS top-shelf fallback. The delivered assets are the 1920×720 and 2320×720 `Background.png` files under `Assets.xcassets/App Icon & Top Shelf Image.brandassets/`. Packaging uses aspect-fill resizing and a centered crop; it does not stretch the reel or split the artwork into panels.

Created November 15, 2026 using the built-in image generation tool, referencing the existing Tonight app icon. No API key or CLI fallback was used. The original icon was not changed. The source PNG is excluded from application resources.

Final prompt:

> Use case: ads-marketing. Create a polished panoramic Apple TV top-shelf background for the personal movie app Tonight. Reference image: existing Tonight app icon supplied via local path; keep its golden film reel, luminous projection beam, violet and warm orange city-at-night visual language. Recompose into a seamless wide cinematic landscape, approximately 3:1, filling the entire canvas with a continuous midnight-indigo sky and city skyline, no flat blank half and absolutely no vertical seams or panel divisions. Put the golden film reel in the left third with its whole silhouette inside the image; continue the rich atmospheric skyline and smooth sky across the full width, leaving clear spacious sky in the right half for app-rendered title. No text anywhere, no letters, no watermark, no sparkle or twinkle glyphs, no decorative stars, no glitter. Keep the reel and city sophisticated and cinematic, luminous but readable in a dark living room. A full-bleed unified composition, not a mockup of a television.

The final fallback uses the continuous artwork without a title overlay. Dynamic Top Shelf uses the actual saved recommendation posters and native system titles instead.
