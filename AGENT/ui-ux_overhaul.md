# UI/UX overhaul

From the second review of the `web/shots` screenshots (dark theme, 2026-10-12).
Each item: problem → proposal. Numbers like `05/21` name folder and shot. Done items of the
first review are in git history.

## Bugs

- [x] 1. Fit image menu (12/30) ticks all 3 entries → they are actions: no ticks.
- [x] 2. Keyboard focus (05/63) and scrubbing (05/62) draw the red invalid border → red only for invalid, focus and scrubbing in the accent.
- [x] 3. Pen hint stays in the status after switching to the move tool (01/34, 36, 37) → clear it on tool change.
- [x] 4. Quick bar runs off the canvas on the right (04/05 line ends) → clamp it to the viewport (it was; the shot clipped it, now it shows the whole bar).
- [x] 5. Objects on the pasteboard are not drawn, only an empty box (04/14) → draw them.
- [x] 6. Cut-off values: `Tint 1 %`, fill bound to a variable `1 %`, `Mode Auto (Mod…`, field bound to a variable `⬡ Nun mm`, font variable editor `So | Re` → minimum widths; a bound field hides its unit.
- [x] 7. `Create from value` and the font variable menu centre and wrap their text (06/34, 06/39) → same menu style as all others.
- [x] 8. Shift H is flip horizontal and auto height, Ctrl D is listed twice → one shortcut per action.
- [x] 9. Deleting a page gives no undo in the toast → toast with `Undo` after destructive actions.
- [x] 10. Preflight error row names only the layer (`Satz sets type in the browser. T…`) → `cause · Name` on every row, so the cause never truncates.
- [x] 11. Screen preset: crop marks and bleed disabled but ticked → disabled means unticked.
- [x] 12. Context menu submenu arrow sits in a keycap (11/02) → plain chevron.
- [x] 13. Overridden master layer (05/23) shows the document panel → select it and show `Overrides master · Reset`.
- [x] 14. Focus ring stays after a mouse click (`+` buttons, layer name, text style select) → `:focus-visible`.

## Consistency

- [x] 15. Spelling `colour` (swatches empty state, preflight gamut) next to `Color` → `color` everywhere.
- [x] 16. Shortcuts as plain text (`Shift W` in the toast, `Esc` in palette and master banner, grey `Enter` in new document) → keycaps everywhere.
- [x] 17. 3 checkbox styles (settings native blue, new document white, panel grey) → 1 style for every checkbox.
- [x] 18. Selects without chevron (`No master`, `Profile sRGB`, font family and style, `Style any`) look like fields → every select has a chevron.
- [x] 19. Selects without prefix (master, `Body` next to bleed, line style) → prefix everywhere: `Master Body` (line style: see 23).
- [x] 20. Per-side input: insets and padding use an icon toggle, stroke a checkbox with a broken grid → icon toggle everywhere, then a 2×2 grid T/R/B/L.
- [x] 21. The per-side toggle sits outside the 2-column grid, fields end ~28 px early → toggle in the section header like the lock.
- [x] 22. Opacity: solid fill has it, gradients not, the picker shows a bare number → `Opacity` label everywhere (the ◐ icon in the narrow paint rows; gradients have opacity per stop).
- [x] 23. Stroke has 2 selects reading `Solid` (paint and dash) → dash select shows only the line preview.
- [x] 24. Eyedropper tool has a pencil icon → pipette.
- [x] 25. Image layers use the rectangle icon → image icon.
- [x] 26. Colour and number variables share the hexagon icon → colour: drop, number: `#`.
- [x] 27. Flip V icon differs in style from Flip H → mirrored pair.
- [x] 28. Rotation `∠` smaller than the letter labels, `°` sits high → same size and baseline.
- [x] 29. Empty and cryptic values: `Off` in number fields, `…` in separations, `Mixed — + replaces` → `–` placeholder, `Mixed · + replaces all`.
- [x] 30. Text wrap sits between Layout and Layer → after Effects.
- [x] 31. Toasts appear bottom centre and bottom right inside the export panel → one place, bottom centre, clear of the page edge.

## App shell

- [x] 32. Right panel header ~4 px above the top bar centre line, no separator below, left header without icon → same header on both sides.
- [x] 33. `Document` twice (panel header and section) → once, in the panel header.
- [x] 34. 1-page document shows `Facing pages`; pages stepper `−` enabled at 1 → `−` disabled at 1 (facing stays: masters keep left and right pages).
- [x] 35. With the left panel hidden the document name disappears → name in the top bar.
- [x] 36. Preflight shield and Export open the same panel; badge `2` red for 1 error + 1 warning → badge counts errors red, only warnings yellow.
- [x] 37. Error status looks like info → red icon and colour.
- [x] 38. Empty layers panel has no empty state → `No layers yet`.
- [x] 39. Status `Created Custom, 8 pages` → `Created A5, 8 pages`.
- [x] 40. Settings has no theme option → `Theme` select (carried over).

## Properties

- [x] 41. Second icon row shows edit points for groups, frames, images (disabled) → hide what does not apply.
- [x] 42. Multi selection align row: bottom align detached, 10 icons squeezed with 5 layers → aligns in 1 row, distribute and spacing in a 2nd.
- [x] 43. Spacing field `↔ 6 mm` shown for 2 layers, not 5, unlabeled → `Spacing` label, shown from 2 layers.
- [x] 44. Mixed fields drop their unit → keep the unit.
- [x] 45. Groups have no rotation, frames no radius → add them.
- [x] 46. Active `Use as mask` looks like a focus ring; a group with a mask is not marked (carried over) → `Release mask` and a mask marker.
- [x] 47. Constraints and sizing selects stand unlabeled under Layout → `Constraints`, `Resizing` sub-labels.
- [x] 48. Auto layout direction ↓ before → → horizontal first.
- [x] 49. Text alignment row with `⋯` overflows the grid → `⋯` inside the grid (checked: flush with the row above).
- [x] 50. Inset labels `↔ 0 | ↕ 0` read as width and height → `Inset H | V`.
- [x] 51. 4th size icon (corners) unclear → removed: auto fit is an action (Ctrl+Alt+C, palette), not a state; the other 3 keep their titles.
- [x] 52. Text stroke rows ordered differently from shape stroke → same order.
- [x] 53. Stroke align icons cryptic → tooltips `Inside`, `Center`, `Outside` (checked: Segmented titles every option).
- [x] 54. No way to add or remove a gradient stop → `+` in the stops header, `−` per stop.
- [x] 55. Invalid input shows a red border without text → tooltip with the reason.
- [x] 56. Star: Ratio and points belong into `Shape` (carried over; checked: Points and Inner radius sit in `Shape`).

## Popovers, pickers, variables

- [x] 57. Picker header shows a lone `Custom` tab for stops and shadows → no tab bar when there is only 1 tab.
- [x] 58. Variable editor: name and mode names do not look editable, `Delete variable` beside `Add mode` → fields, delete moved to the context menu.
- [x] 59. Edit swatch name field squeezed by `Spot color` → name full width.
- [x] 60. Swatch row `RGB ⚠` without explanation → tooltip.
- [x] 61. `Upload ICC…` in the profile select without separator → separator.
- [x] 62. Line end select without preview → arrow icons.

## Text

- [x] 63. OpenType rows `Auto | 196 | 196` and `Auto | 11 | 11` unlabeled → row labels and readable options.
- [x] 64. Unlabeled type selects (`As typed`, `Normal position`, `No decoration`, `No list`) → prefixes `Case`, `Position`, `Decoration`, `List`.
- [x] 65. `Keep 1` unclear; drop cap `Characters` enabled at 0 lines → `Keep lines`, disable.
- [x] 66. Insert character: only page number has keycaps, glyph chips tiny → glyph left, name, shortcut right.
- [x] 67. All characters shows no name on hover → title with name and code point. (checked: each glyph has a title with name and code point, the footer names the hovered one)

## Canvas

- [x] 68. Resize shows no size, rotate no angle → label at the pointer.
- [x] 69. Size label is magenta like snap distances → neutral label, centred under the box. (done with 68)
- [x] 70. Distance labels `11 mm` and `29 mm` overlap (04/12) → move the shorter one aside. (checked: labels move apart since f7f8807, snap.spec asserts no overlap)
- [x] 71. Drawing a rectangle shows radius handles → only after drawing.
- [x] 72. Quick bar for text, wrap and threading sits over the text → above the frame, below if no room.
- [x] 73. Quick bar image shows a meaningless `∅` fill chip → hide.
- [x] 74. Adjust image: values far from the labels between − and + → slider with the value right.

## Layers, pages, export, dialogs

- [x] 75. Spread layers header reads `Layers` and the page is a grey group row → `Layers · Pages 2–3`.
- [x] 76. Switcher marks only `2` of spread `2 3` → mark both.
- [x] 77. Overview labels `2B 3B` read like names; master tile `B  · Body` gap → `2 · B`, even gap.
- [x] 78. Page range error `Pages 1 to 1, like 1-3, 5` → `Pages 1–8, e.g. 1-3, 5`, `Only page 1` for 1 page.
- [x] 79. `JPEG quality` shown when images are kept → only when images are resampled. (kept: the quality also re-encodes PNG and converted images at full resolution)
- [x] 80. `Export with 3 errors` looks like the normal primary button → warning style.
- [x] 81. Black separation dot is hollow → filled.
- [x] 82. New document: `Open file…` broken styling, headings of different size, format sizes wrap (`420 mm × / 594 mm`), pages without stepper → fix styling, `420 × 594 mm` on 1 line, stepper.
- [x] 83. Shortcuts dialog: keys left or right aligned per section, recording row not highlighted → keys right, highlight the row.
- [x] 84. Settings is a full-height dialog with 3 options and autofocus → compact, no autofocus.
- [ ] 85. Find: `Replace` sticks to the field, `Replace all` not flush with the close button → even gaps, flush right.
- [ ] 86. Shape menu: ~42 px left padding, ~12 px right, no tick for the current shape → even padding, tick.
