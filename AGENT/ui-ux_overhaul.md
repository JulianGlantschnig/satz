# UI/UX overhaul

From a review of all 237 screenshots of `web/shots` (`/tmp/satz-shots/<folder>/<nr>`, the same as the Figma file).
Each item: problem → proposal. Numbers like `05/21` name folder and shot.
Not checked: live interaction, hover states and tooltips beyond the shots, keyboard navigation; alignment was judged by eye on the 2× shots, not measured.

## Priorities

- [x] **Unlabeled fields** (Hug/Hug, Fixed/Fixed, Left/Top, shadow X/Y, bare `%` for fill and layer opacity, auto size icons, gradient stops `0 % | 100 %`) → inline prefix like `W`/`H`/`Limit`: `W Hug`, `H Hug`, `Opacity 100 %`, `Pos 0 % · Alpha 100 %`.
- [x] **`−` means 4 things** in the quick bar (no stroke, add, remove, unclear) → empty stroke slot shows a struck-through stroke swatch, `+` adds, removing only in the panel.
- [x] **Dropdowns are always ~425 px wide**; in the right column, and in the quick fill and fit menus, they open shifted → min width = trigger width, aligned to the trigger edge.
- [x] **Stroke block layout differs per type** (rectangle, polygon/star, 2 shapes, 5 layers) → 1 fixed 2-column grid: `Weight | Style`, `Align | Joins`, `Caps | Start/End`, `Overprint`.
- [x] **Text sections come after Fill, Stroke, Effects** → for text frames put Text and Text frame right after Layout.
- [x] **Layers: selection and hover share one grey** → selection in the accent colour.
- [x] **No feedback for overset, threads, overrides** → overset badge `+42 words`, connection line between threaded frames, loaded cursor while threading, override marker plus `Reset to master`.
- [x] **New document is silently CMYK** → fields `Colour RGB/CMYK` and `Bleed 3 mm` under the formats.
- [x] **Colour pickers without swatches** (shadow, gradient stop, quick fill with only None/Black/White) → one picker everywhere with Swatches | Custom | Variables.
- [x] **Magenta is overloaded** (snapping, distances, master banner, master letters) → magenta only for measuring/snapping; masters get their own colour and `B · Body`.
- [x] **Rectangle icon is an empty square** and looks like an unchecked checkbox (layers, properties header) → filled square or square with corner handles.
- [x] **Shortcut notation varies** (`Ctrl+Shift+E` vs `Ctrl Shift E`, `⌘` before every palette command) → 1 keycap component everywhere, per platform.

## App shell

- [x] Panel header says `Page` but shows document and page settings, partly twice → without selection 2 sections `Document` and `Page`, each setting once.
- [x] RGB profile is static text, CMYK profile a dropdown → both `Profile ▾`, disabled when there is no choice.
- [x] `N` is page count and polygon points → `Pages` and `Points`.
- [x] Page navigation has no total → `3 / 12`.
- [x] `>` turns into `+` on the last page → disable `>`, `+` separate and always visible.
- [x] Page navigation width depends on the document → fixed width.
- [x] Spread pill does not mark the current page → highlight the active half.
- [x] Page does not re-centre when panels are hidden → re-centre if it was centred.
- [x] Shift W gives no hint how to get the UI back → toast `Shift W shows the interface again`.
- [x] Export tooltip says `Export PDF` though PNG/JPEG exist → `Export`.
- [x] `List the fonts of this computer` too long → `Use local fonts`.
- [x] Layout grids header has an extra icon → only `+` like the other sections.
- [ ] Dark/Light dropdown has no label → `Theme ▾`.
- [x] Text style rows indented ~10 px → flush with swatch rows.
- [x] Swatch values without C/M/Y/K labels → `C0 M55 Y100 K0` or tooltip.
- [x] Swatches section has no chevron → collapsible like Layers.
- [x] Auto layout children listed in reverse → list in layout direction.

## Dialogs

### New document
- [x] Format names wrap onto 2 lines → shorter labels or wider tiles.
- [x] Selected state depends on focus → own selected state with accent border.
- [x] Custom thumbnail looks like A5 → dashed sheet with `+`.
- [x] Button reads `Create Custom` → always `Create`.
- [x] `Open file…` has a magnifier and sits under Examples → folder icon, secondary button bottom left.
- [x] Esc opens the booklet → Esc only closes.
- [x] `Examples` heading baseline is off.
- [x] Poster description ends in an orphan word.

### Shortcuts
- [x] Gestures (drag, scroll) shown as keycaps → italic text.
- [x] Cryptic labels → full sentences.
- [x] 2-line row has a tall keycap → keycap top-aligned, fixed height.
- [x] Reset button shifts the header → reserve its space.
- [x] Remapped shortcuts have no marker → dot plus per-row reset.
- [x] Recording gives no Esc hint → `Press a key · Esc cancels`.
- [x] Search matches not highlighted; dialog height jumps → highlight, fixed height.
- [x] `100 %` has a stray space.

### Settings
- [x] Focus lands on X → first field.
- [x] `Layers: Of the page` unclear → `Layers panel shows: Current page / Whole document`.
- [x] Checkbox rows built differently → one row layout.
- [x] Modal too large for its content.

### Command palette
- [x] `⌘` before every command → no icon or one per command.
- [x] Group `Commands` appears twice.
- [x] Ranking off, matches not highlighted → prefix matches first, matches bold.
- [x] Shortcut `.` invisible; shortcuts are text → keycaps.

### Find & replace
- [x] Matches not highlighted on the canvas.
- [x] Fields have different widths.
- [x] `Case` sticks to the next checkbox.
- [x] `0 found` has no error state → red field border.
- [x] `All` ambiguous → `Replace all`.
- [x] `Any style` unclear → `Style: any`.

## Toolbar

- [x] Eyedropper uses a pencil icon → eyedropper icon.
- [x] Shape menu: no mark for the current shape, no shortcuts for Polygon/Star, opens offset.
- [x] Path bar icons unclear, `Done` is text → tooltips, `Done` as primary button with `Enter` hint.
- [x] Panel toggles sit among the tools → separator, move right to the help group.

## Canvas

- [x] No W×H label while drawing shapes and text frames → live label under the cursor.
- [x] 3 distance labels overlap; a label covers its line → labels on the line in a pill, offset on collision.
- [x] Stray handles during marquee.
- [x] Pen: no hint how to finish/close → `Enter finishes · click the start point closes`.
- [x] Path edit: hovering a point gives no feedback (both shots identical); quick bar stays during path edit.
- [x] New text frame has no inset; text touches the frame edge.
- [x] Text frame has only corner handles → side handles for width alone.
- [x] Text quick bar wider than the page column (`No style` select ~150 px) → style as icon button, font and weight in one select.
- [x] Quick bar covers content above the frame; in 43 it sits on the guide → place below when there is no room above.
- [x] Overset `+` covers the last glyph, no count.
- [x] Threading: no loaded cursor, no connection line; in-port barely visible.
- [x] Crop mode hard to tell apart; panel identical to normal mode (05/21 = 05/20) → dim outside, show image bounds, panel `Crop · Done`.
- [x] Image: 2 kinds of handles (corner squares, white inner dots) unexplained.
- [x] Placing an image shows an empty blue rectangle → image preview.
- [x] Layout grid column stripes cross the header and bleed → clip to the margins.
- [x] Square grid too faint.
- [x] Dragging a guide: 2 unlabeled magenta labels → `↑ 6.7 mm · ↓ 11.3 mm`.
- [x] Guide hover shows no change.
- [x] Text wrap offset not shown → dashed outline.
- [x] Overridden master layers have no marker on canvas or in layers.
- [x] `Use as mask` is a checkbox for 1 object, a button for several → button everywhere.
- [x] Multi selection fill shows one colour instead of `mixed`.
- [x] Distribute icons look disabled for 2 objects (15) → hide instead of grey.

## Quick edit bar (12)

- [x] `Inside` (group, mask) cryptic → `Align to: Selection/Parent` icon toggle with tooltip.
- [x] `15 two shapes (boolean bar)` has no boolean ops → 4 boolean icons for 2+ shapes.
- [x] Line with arrow (06) shows no arrow heads → `Start ▾ End ▾`.
- [x] Stroke swatch (white square, black core) looks like a stop icon → ring swatch in the stroke colour.
- [x] `≡ 1 pt`: icon reads as paragraph align; big gap between number and unit → stroke weight icon, unit right after the number.
- [x] `N − 3 +`: number clipped and faint → `Points`, min width.
- [x] Image (20–22): first item `−`, icons unlabeled; no `RGB → CMYK` hint in a CMYK document.
- [x] Fit menu (30): no mark for the current option, empty indent → use the check column.
- [x] Adjust (31): 3 steppers in 2 columns, one cell empty, no reset → 3 rows plus `Reset`.
- [x] Quick fill (32): only None/Black/White → document swatches plus `Custom…`.
- [x] Auto layout (18, 19): `Hug | Hug`, `Fixed | Fixed` unlabeled → `W Hug ▾ H Hug ▾`.
- [x] Bar covers text (wrap object, image) → avoid content, allow placement below.

## Properties

- [x] Arrow: caps/start/end/joins crossed → `Start ▾ End ▾` in 1 row.
- [x] Ellipse: `Start °` next to `Sweep %` → both °; `Ratio` → `Inner radius`.
- [ ] Star: Ratio and N under Layout → own section `Shape`; link button far right.
- [x] Shadow: X/Y look like position → `Offset X/Y`; colour and 40 % unlabeled.
- [x] Stroke: 2 dropdowns `Solid` (paint, dash) → dash style with pattern preview; stroke icons unlabeled.
- [x] Overprint always visible → only in CMYK documents.
- [x] Constraints and sizing dropdowns unlabeled.
- [x] Frame: `Clip content` next to the angle field → own row.
- [x] Auto layout padding as T R / B L → horizontal/vertical, expandable to 4.
- [x] Auto layout: `−` next to the direction toggle; `Packed` → `Spacing: Fixed / Space between`.
- [x] Text frame header shows the first words → `Text frame`.
- [x] Auto size icons unlabeled; inset icons tiny.
- [x] Gutter `4.23 mm` → round.
- [x] Baseline field shows `Off`.
- [x] `Lines` and `Min` rows appear only sometimes, layout jumps → always show, disable when not applicable.
- [x] Vertical align buttons full width.
- [x] Letter spacing in %, spacing in pt.
- [x] `#` button opens special characters → `Ω`.
- [x] Image section has no `Replace` and `Fit`.
- [x] Text wrap offsets labelled `X/Y`, row half empty → `Offset`.
- [x] Field bound to a variable (51): chip shows `¿?` and drops the unit.
- [x] Hexagon replaces the chevron only on hover; bound fill has no marker → one binding marker, always visible.
- [x] `Click + to replace mixed fills` wordy → `Mixed — + replaces`.
- [x] Mixed: Stroke still shows controls while Fill does not.
- [x] Icon rows (align, flip, boolean) without group labels → tooltips and separators.
- [ ] Mask shape shows the group's props (03 = 04), not selectable or distinguishable.

## Popovers

- [x] CMYK picker fields clipped (`M 73.`) → integers or wider fields.
- [x] Blend modes: no group separators → separators after Darken, Lighten, Contrast.
- [x] Format menu: `Custom` greyed out.
- [x] Variable editor opens far from its row.
- [x] Variable name and mode are text in one state, inputs in another.
- [x] `Delete variable` weighs like `Add mode` → red, separated.
- [x] Variable rows show a swatch or `−`.
- [x] `auto (Mode 1)` lower case.
- [x] `No number variables yet` → `Create from value`.
- [x] Empty swatches tab only explains → button `Save as swatch`.
- [x] Swatch icons ⊙/⊕ (spot/process) unclear → badge `Spot`.
- [x] Context menu `Delete` not red.
- [x] Tooltip covers the neighbouring field → show above.

## Text

- [x] Type options mixes too much; first-line indent is an icon, the rest text; `After` lives elsewhere; `Drop`, `Chars`, `Keep` cryptic; full-width `Add tab stop` in the middle → 3 groups (Indents & spacing, Drop cap, Tabs), text labels.
- [x] OpenType 2-part toggle unclear; Lining/Oldstyle and Proportional/Tabular exclusive → segmented controls.
- [x] Insert character: tiny grey glyphs; All characters without names → name as tooltip and footer.
- [x] Font select has no search.
- [x] `Create text style` inside the select → `+` next to it.
- [x] Style applied with overrides shows no marker → `Heading*` plus reset/update.
- [x] Shot 31 `word selected` shows only a caret.

## Layers, swatches, pages, masters

- [x] Drop above shows no insertion line (07).
- [x] Page with a master shows no master entries → collapsed group `Master B`.
- [x] Spread has page headers, a single page none.
- [x] Master layer names duplicated (#, Rule, EARTHRISE) without left/right grouping.
- [x] Edit swatch: no hex field; RGB picker for CMYK → 4 sliders for CMYK.
- [x] Page labels `1 C` use letters the masters column does not show → `B · Body`.
- [x] Empty slot left of page 1 solid, after the last page dashed with `+` → both dashed or drop the left one.
- [x] Dragging a page: no drop indicator or ghost.
- [x] Page menu: `Master like page` → `Create master from page`; add `Apply master`, `Insert page`.
- [x] Master menu lacks `Duplicate master`.
- [x] Master rename field overflows, name cut (`ody`).
- [x] While editing a master, the master slot shows `auto (Light)`, a different meaning in the same place.
- [x] Page switcher shows no total.

## Preflight & export

- [x] `Images Keep` looks like an input.
- [x] `JPEG − Lossless +` unclear → `JPEG quality ▾` (Lossless, 90, 75).
- [x] Page range `7-x` only greys out the button → error text under the field.
- [x] PNG/JPEG export has no resolution field.
- [x] Export toast bottom left, far from the button.
- [x] Badge `0` always visible → green check or nothing.
- [x] Separations at first open (20): spot `Satz Orange` missing, `Highest 0 %` → loading state `…` instead of a false 0.
- [x] Separation rows are boxed cards, other checkboxes are not.
- [x] Black dot nearly invisible on dark ground.
- [x] Gamut (22): checkbox off, no marks visible → fix the shot or the feedback.
- [x] Issues (23): `Background ink at 297 %, above the limit` wraps → `Background · 297 % ink` in 1 line, page as link.
- [x] `Under pointer: Point at a colour` is an instruction in a value slot → `—` plus grey hint.
- [x] Overset issue text truncated.

## Context menus (11)

- [x] 19 items → submenu `Transform` for flip, mask, flatten.
- [x] `Delete` not red, between Duplicate and Group → last, red.
- [x] Missing: `Bring forward` / `Send backward`, `Copy/Paste style`, `Apply master`.
- [x] `Hide selection` / `Lock selection` → `Hide` / `Lock`.
- [x] `Page overview` has a barely visible marker; `Add page` has no shortcut.
