# Review and fix plan: uncommitted v1.5.0 changes

## Goal
Review the 22 modified and 7 untracked paths, which are all unstaged. The v1.5.0 content is personality painters, camera `orbit`/`static` modes, gradient/glow backgrounds, the `pastel_harp` score, scene dissolves and TTS rate/pitch.

The first pass was shallow. This one is based on reading `visual.py`, `text.py`, `camera.py`, `audio_dsp.py`, `storyboard.py` and `render_engine.py`.

## Verified green
- `ruff check` passes and `ruff format --check` passes (56 files).
- `mypy --strict` is clean.
- 375 tests pass.
- The demo storyboard validates.
- The `VALID_SFX`, `VALID_PAD_STYLES` and `VALID_TRANSITIONS` sets in `storyboard.py` match what the synth and renderer implement.

## Findings

### Bugs
| # | Where | Issue | Severity |
|---|---|---|---|
| 1 | `visual.py` `paint_typewriter_text` | The cursor test `reveal < len(text) + hold` compares characters with seconds. `hold` is documented as a time in seconds, but here it acts as a number of extra characters. The cursor lingers for the wrong duration. `reveal >= 0.0` is always true. | Medium |
| 2 | `text.py` `paint_quote_card` | With `alpha < 1`, the card is drawn by `_paste_soft_pill`, which writes straight to `cv.image` and ignores the camera. The card text still uses the camera. Under zoom or orbit the card and its text drift apart. `paint_kinetic_captions` already handles this by setting `cv.camera = None`. The quote card does not. | Medium |
| 3 | `visual.py` `paint_typewriter_text` | Each glyph is drawn separately with an extra advance of `getlength("i")`. This loses kerning, and the extra spacing is an undocumented magic number. | Low |
| 4 | `visual.py` docstring | It claims motion depends on `seed`, but no painter uses `seed`. | Low (docs) |

### Performance
- `paint_background` rebuilds a 64×64 gradient, the vignette mask (4096 `putpixel` calls) and a Gaussian blur per glow orb on every frame. None of these depend on time except the glow drift. Cache the gradient and vignette per `(size, params)`.
- `pastel_harp_stereo_at` costs about 0.38 s per second of audio in pure Python, which is about 23 s for a 60 s video. It is called from two sites in `audio_dsp.py` (lines 347 and 438) with duplicated logic. This is acceptable under the stdlib-only rule, but it's worth noting.

### Repo hygiene
1. `projects/` (6.6 MB, with `audio/`) is untracked and not ignored. AGENTS.md forbids committing rendered outputs.
2. `SKILL.md` is 128 lines against the 120-line cap.
3. The Cormorant fonts and their OFL license file must be committed together, and the license kept verbatim.
4. `--rate` and `--pitch` are not validated. A bad string only fails inside edge-tts and then silently falls back to the estimated timing.
5. `CHANGELOG.md` should mention the dynamic Three.js timeout (`max(240, 1.5·frames+90)`), the new `--pad-tail`, `--reuse-plates` and scene dissolve options.

## Proposed changes
1. **`visual.py`:** fix the typewriter cursor to use seconds. Keep per-glyph drawing but remove the `getlength("i")` hack in favour of measured `getlength(text[:i+1])` offsets. Fix the docstring.
2. **`text.py`:** in `paint_quote_card`, set `cv.camera = None` for the card and text when `alpha < 1`, matching the captions fix. Alternatively, project the card box through the camera.
3. **`elements/scenes.py`:** cache the gradient and vignette masks in a module-level `lru_cache` keyed by size, colours and direction.
4. **`tts_align.py`:** validate `--rate` against `^[+-]\d+%$` and `--pitch` against `^[+-]\d+Hz$`. Reject bad values with an argparse error.
5. **`SKILL.md`:** move the "Scene visual quality checklist" into `references/storyboard-guide.md`, leaving a one-line link.
6. **`.gitignore`:** add `projects/**/audio/` and rendered media.
7. **`CHANGELOG.md`:** add the missing notes.
8. **Tests:** add one for typewriter cursor timing, one for quote-card/camera alignment, one for rate/pitch validation, and one for gradient cache equality.

## Open questions
> [!IMPORTANT]
> **`projects/`:** commit the bundle (brief, script, storyboard, svg) without audio and renders, or ignore the whole folder?

> [!NOTE]
> Should I split this into several commits (visuals, camera, audio, docs) or one v1.5.0 commit? Splitting makes the history linear and reviewable.

## Verification plan
- `ruff check --no-cache scripts/ tests/`
- `ruff format --check --no-cache scripts/ tests/`
- `python3 -m mypy scripts/`
- `.venv/bin/python -m pytest tests/ -q` (the system `python3` has no pytest)
- `scripts/ci_gates.sh` (the full 9-gate run, including thumbnails and the draft render)
- Manual: render thumbnails for a storyboard that uses a typewriter, an alpha quote card and a camera orbit. Check that the card stays aligned with its text.
