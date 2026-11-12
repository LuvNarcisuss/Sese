# Media and typography

## Hosted Shorts

The default Shorts feed uses 9:16 H.264 MP4s and matching JPEG covers from the public `editorial/shorts/v1/` prefix. Each clip is 720 × 1280, 30 fps and silent. The [Shorts media manifest](ShortsMedia.json) records authors, exact source URLs, licenses, excerpt timing, and SHA-256 digests.

| Short | Source and license |
| --- | --- |
| How a fox costume moves | [Wide take](https://www.pexels.com/video/enchanting-female-in-vibrant-fox-themed-costume-32542808/) and [close-up](https://www.pexels.com/video/artistic-cosplay-portrait-with-fox-ears-32542810/), TBD Tuyên. The two-shot edit adds original costume commentary. [Pexels License](https://www.pexels.com/license/) |
| Follow the conga line | [NärCon Sommar 2025](https://commons.wikimedia.org/wiki/File:N%C3%A4rCon_Sommar_2025_-_conga_line_of_furries.webm), Rose Abrams. The portrait edit and cover use [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). |
| A costume meet-up hug | [Diti hugs Natalie](https://commons.wikimedia.org/wiki/File:Diti_hugs_Natalie.ogv), [Dimitri Torterat](https://diti.me/). Trimmed, reframed and muted. [CC BY 2.0 France](https://creativecommons.org/licenses/by/2.0/fr/) |
| Ask before you snap | [Fursuit Etiquette](https://commons.wikimedia.org/wiki/File:TITANIA_-_Fursuit_Etiquette_%282024%29.webm), TITANIA. Source edit by Jayvee Enaguas. Reframed, muted and captioned. [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) |

## Earlier publisher sources

These records preserve their catalog IDs and original sources for existing interactions and relevant catalog details. Disney film and trailer distribution permissions are not on record.

| Title | Source | Delivery |
| --- | --- | --- |
| Fur of a Skunk | [Walt Disney Animation Studios](https://video.disney.com/watch/fur-of-a-skunk-clip-zootopia-52a6c8bd00ca6db8f3d66e46) | Publisher player |
| Elephant in the Room | [Walt Disney Animation Studios](https://video.disney.com/watch/elephant-in-the-room-clip-zootopia-52a58cd278a2716e6d326035) | Publisher player |
| Judy Hopps Costume Evolution | [Disney Style](https://video.disney.com/watch/judy-hopps-costume-evolution-disney-style-55aa81bc4baee7cf2bb99b82) | Publisher player |
| Judy and Nick at Disneyland | [ANDA](https://www.youtube.com/watch?v=4TLk5ZyGN9w) | YouTube source |
| Japan Expo Cosplay | [The Eighty Sixth Floor](https://theeightysixthfloor.com/japan-expo-cosplay-2022/) | Publisher source |
| Flash at the DMV | [Walt Disney Animation Studios](https://www.youtube.com/watch?v=bY73vFGhSVk) | YouTube source |
| Gary at the Gala | [Disney Japan](https://www.disney.co.jp/movie/zootopia2/news/20251204_01) | Official Japanese-dubbed film clip on the publisher's player |
| Zootopia 2 Official Trailer | [Disney Video](https://video.disney.com/watch/zootopia-2-trailer-63b2807aa1399deb74651fcd) | Publisher source |

## Photos

- **Anime Expo 2016**, Oliver Ayala / Dapper Geek News. [Source and attribution](https://commons.wikimedia.org/wiki/File:Cosplay_of_Judy_Hopps_and_Nick_Wilde_from_Zootopia_at_Anime_Expo_2016_(28086759383).jpg). [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/). Original unmodified JPEG, 864 × 1080, 441,664 bytes, SHA-256 `fb9f94346c8a4cd114469ae5b66f7e067dddd999ae7baedecc409ad20827f6e0`. The image was visually checked for the real Judy and Nick costumes and retained the photographer's credit. It is in the gallery and supplies three optional avatars: Judy Hopps, Nick Wilde, and the duo. The circular avatar choices crop the display only. The profile editor links to the photo credit and license.
- **KodachiCon 2026**, Rose Abrams. The gallery loads the 1536 × 2048 JPEG from Supabase Storage at `editorial/sese-media-v1/fan-duo.jpg`. EXIF metadata was removed, and the image data was preserved. SHA-256 `48b8b85ac9d672f4154b4fd2c57fc31b26aee82752186e292d9baa49407abcc7`. [Source and attribution](https://commons.wikimedia.org/wiki/File:KodachiCon_2026_19_-_Judy_%26_Nick.jpg). [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

Photographed people appear as editorial subjects. They are not presented as accounts, endorsers or message recipients.

Member avatars use the selected portrait or a stable choice from the credited cosplay photos. Shorts editorial creator pages use portraits from the same set as themed editorial imagery, with the portrait source and the clip creator credited separately.

## Additional cosplay sources

The following sources are retained for selection. Preview-frame or photo-byte retrieval is still pending, so these entries have no in-app media card.

| Material | Original source | Credit or license |
| --- | --- | --- |
| Judy and Nick cosplay duo | [YouTube Short](https://www.youtube.com/watch?v=-ZsQw3SzmTk) | The 86th Floor: Cosplay and Cons |
| Judy and Nick costume showcase | [YouTube Short](https://www.youtube.com/watch?v=Dx5UJNyd82w) | The 86th Floor: Cosplay and Cons |
| Judy and Nick in Times Square | [TikTok original post](https://www.tiktok.com/@bennydrama7/video/7566285565943893278) | Benito Skinner and Mary Beth Barone |
| Judy and Nick at WonderCon 2018 | [Wikimedia Commons photo](https://commons.wikimedia.org/wiki/File:Nick_and_Judy_WonderCon_2018.jpg) | RightCowLeftCoast, CC BY-SA 4.0 |
| Judy and Nick at Animation-Comic-Game Hong Kong 2022 | [Wikimedia Commons photo](https://commons.wikimedia.org/wiki/File:Cosplayers_of_Judy_and_Nick_at_ACGHK_2022_-_D2T1655.jpg) | Jason Kwok, CC BY-SA 4.0 |

## Generated artwork and type

ImageGen generated every navigation icon, toolbar icon, launcher icon, portrait background, and district image separately. The [artwork manifest](Artwork.json) records the source, Storage object paths, and hashes. The interface uses Fredoka and Comic Neue, with their SIL Open Font License files in the font resource folder. UIKit-provided system surfaces follow the operating system's accessibility and typography behavior.

## City exploration and wallet artwork

The interactive city map uses an ImageGen 4:3 aerial illustration of City Center, Sahara Square, Tundratown, and Rainforest District. UIKit overlays the district controls on the corresponding areas. The wallet and its activity use a separate ImageGen diamond with a transparent canvas. The artwork manifest records both source files and the verified public Supabase object hashes.

## Storage and build delivery

- The two gallery photos and 21 generated images are stored in Sese's `editorial` bucket. The gallery, member avatar choices, and interface artwork load over HTTPS with an in-memory image cache. Chat attachments use the private `chat-photos` bucket.
- The Xcode target fetches `launcher.png` and verifies the manifest SHA-256 before asset catalog compilation. Xcode's `AppIcon` catalog keeps its JSON descriptor in Git and uses the ignored `Art.png` as a generated build input. A clean build needs HTTPS access to Sese's Supabase Storage.
- For Shorts replacements, download a licensed source into a temporary directory. Inspect representative frames and export a 9:16 fast-start MP4 and a matching JPEG. Upload both to a versioned Storage path and verify public HTTPS, SHA-256, and MP4 byte-range support before switching catalog references. Record the source, license and edits in the manifest, then remove the temporary copies. Keep image and video payloads out of Git.
