---
name: visual-verification
description: Capture and inspect native Windows, 3D, animation, or video evidence; route browser UI verification to Playwright.
---

# Visual Verification

Use this Skill for visual verification of native Windows apps, 3D scenes, animations, video, and same-session A/V evidence. For Web UI or browser interaction, use Playwright instead; do not use screen capture as a substitute for browser-level verification.

Store evidence in a temporary run directory, normally under `%TEMP%\agent-verification-lab`. Do not automatically upload, commit, or delete evidence. Treat captures as potentially sensitive: confirm that visible windows, notifications, personal data, credentials, and third-party content are appropriate to record before capture.

## Static evidence

Capture the required desktop, region, or exact visible window, then inspect the actual PNG with `view_image`. A successful command or file existence is not visual verification.

```powershell
$codexHome = if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$skill = Join-Path $codexHome 'skills\visual-verification\scripts'
pwsh -NoProfile -File "$skill\screenshot.ps1" -Mode region -X 100 -Y 100 -Width 1280 -Height 720
```

`window` mode requires exactly one exact window title or HWND. It captures that window's screen bounds, not an isolated compositor surface, so occlusion, overlays, and minimized windows can invalidate the evidence.

## Motion evidence

Record a short run, extract a bounded ordered frame sequence, generate a labeled contact sheet, and inspect the contact-sheet PNG with `view_image`. Combine the visual result with relevant test output, logs, and state; each source supports a different claim.

H.264 `yuv420p` recordings preserve even captured dimensions; an odd captured width or height receives one black pixel of padding on the right or bottom respectively, without cropping.

```powershell
$codexHome = if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$skill = Join-Path $codexHome 'skills\visual-verification\scripts'
$recordOutput = & pwsh -NoProfile -File "$skill\record.ps1" -Duration 5 -Fps 20 -Mode region -X 100 -Y 100 -Width 1280 -Height 720
if ($LASTEXITCODE -ne 0) { throw 'Recording failed.' }
$runDirectory = ($recordOutput | Where-Object { $_ -like 'RUN_DIRECTORY=*' } | Select-Object -Last 1).Substring('RUN_DIRECTORY='.Length)
pwsh -NoProfile -File "$skill\extract-frames.ps1" -InputVideo (Join-Path $runDirectory 'recording.mp4') -RunDirectory $runDirectory -Interval 0.5 -MaxFrames 20
pwsh -NoProfile -File "$skill\contact-sheet.ps1" -InputDirectory (Join-Path $runDirectory 'frames') -RunDirectory $runDirectory -Columns 4 -Interval 0.5 -CellWidth 640
```

The contact sheet defaults to `contact-sheet.png` in the parent run directory. It only accepts `frame-*.png` inputs, orders them numerically, normalizes each source into a centered black 16:9 cell derived from `CellWidth`, labels timestamps, and refuses to replace an existing output unless `-Overwrite` is supplied.

Fail closed: stop and report a clear error if FFmpeg is unavailable, the requested capture target is ambiguous or invalid, the frame input is empty, output already exists without `-Overwrite`, or the resulting image cannot be inspected. Do not infer visual success from logs alone.

## A/V evidence

For synchronized A/V, select a DirectShow audio source from the current machine and call `record-av.ps1`; it opens audio and video in one FFmpeg session. Inspect the capture with `inspect-media.ps1`, then render a waveform and generic onset, peak, silence-start, and silence-end events with `waveform.ps1`. Compare timestamps with `evaluate-sync.ps1`, whose offset is audio minus visual: positive is audio-late and negative is audio-early.

Each successful visual operation emits absolute `RUN_DIRECTORY`, `OUTPUT_PATH`, `KIND`, and `RESULT_JSON` records. Reuse the emitted run directory for related work and inspect `result.json`; do not invent a run path or overwrite an existing output without `-Overwrite`.

## Speech evidence

`analyze-speech.ps1` uses the isolated WhisperX environment when it is available and emits normalized language, segment, word, backend, and alignment provenance. `REQUIRES_BACKEND` is a conditional unavailable-backend state, not a successful transcript. Use forced alignment only when the transcript is already known.
