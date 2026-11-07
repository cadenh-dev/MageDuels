# Rendered Chant Voice Pipeline (OpenUTAU)

The game currently ships **procedural** chant voices (`scripts/audio/voice_synth.gd`).
This folder is the next-pass pipeline for a real singing-voice render.

## Installed locally

| Item | Path |
|---|---|
| OpenUTAU 0.1.576 (portable, MIT) | `%USERPROFILE%\Apps\OpenUtau\OpenUtau.exe` |
| Tsukuyomi-chan UTAU voicebank | `%USERPROFILE%\Apps\OpenUtau\Singers\つくよみちゃんUTAU音源` |
| Starter project | `tools/voice/chant_demo.ust` |

Neither the OpenUTAU app nor the voicebank is committed to this repository.
Only rendered audio should ever be committed.

## Render

1. Run `powershell -ExecutionPolicy Bypass -File tools/voice/open_render.ps1`
   (or open `chant_demo.ust` from OpenUTAU).
2. Select the singer **つくよみちゃんUTAU音源** if OpenUTAU asks.
3. `File → Export Audio → Export Wav Files`.
4. The project exports next to the `.ust` in an `Export` folder.
5. Convert to OGG if desired, then replace or layer the procedural voice bank.

The demo sings `い ぐ な み と` / `と て ら` — an approximation of **IGNA MITT**
and **TUTELA**. UTAU is Japanese CV/CVVC; Latin incantations need kana mapping.

## Suggested kana mapping

| Rune | Kana | Notes |
|---|---|---|
| IGNA | いぐな | fire |
| GLACIA | ぐらしあ | frost |
| VOLTA | ゔぉるた / ぼるた | storm; `ゔ` depends on the bank |
| TERRA | てら | earth |
| ARCANA | あるかな | arcane |
| VANA | ゔぁな / ばな | void |
| MITT | みっと | bolt |
| QUAERO | くえろ | orb |
| RADIA | らでぃあ | beam |
| RUPTA | るぷた | nova |
| MURUS | むるす | ward |
| TUTELA | とぅてら / つてら | aegis |

Use one note per syllable, then pitch the phrase to the element's arpeggio.

## Licensing / credit

**Tsukuyomi-chan UTAU Voicebank** (CV. Rei Yumesaki) —
<https://tyc.rei-yumesaki.net/material/utau/>

Terms (summary, read the full Japanese/English page before shipping):

- Personal and commercial use allowed.
- Use in other software, including games, allowed.
- Rendered audio may be used; credit is optional for music-material use, but we
  will credit it.
- **Do not redistribute the voicebank files, raw samples, or the extracted
  library.** Ship only rendered audio.
- Do not publish the voicebank as a sampling library.

If this pipeline ships, add this credit to the game and itch page:

```text
Vocal: Tsukuyomi-chan UTAU Voicebank (CV. Rei Yumesaki)
https://tyc.rei-yumesaki.net/material/utau/
```

## Why not Vocaloid

Vocaloid is proprietary and each voicebank has its own license. OpenUTAU + a
free-material UTAU voicebank gives a legally clear, offline, reproducible path
with no runtime dependency in the Godot build.

> The kana table below refers to the old rune words. It is retained as a historical voice-mapping reference and has not been re-derived for the new words.
