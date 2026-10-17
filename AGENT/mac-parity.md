# Mac app vs. web Satz: parity audit

Reference: `web/` at main 3c984d4 (upstream LeonhardWeiler/satz has nothing newer).
Checklist: every Playwright spec title in `web/e2e/*.spec.ts` (267), plus FEATURES.md.
Status: ok = the Mac app does it, gap = to do, fixed = done in this audit, n/a = web only.

## Not applicable on the Mac
- webgl.spec (WebGL 2, wasm loading), offline.spec (PWA install): native app.
- file.spec autosave download / reload keeps document: NSDocument autosave and versions.
- "new asks before it discards changes": New opens another window on the Mac.
- "focus moved after a click shows no ring": AppKit focus rings.
- "at 880 px the top bar fits": toolbar overflows natively.

## Gaps found
1. Align shortcuts ⌥A ⌥H ⌥D ⌥W ⌥V ⌥S, distribute ⌥⇧H ⌥⇧V, tidy ⌃⌥⇧T (align.spec).
2. Boolean shortcuts ⌥⌘U ⌥⌘S ⌥⌘I ⌥⌘X and menu items (align.spec).
3. F2 renames the selected layer (layers.spec keyboard walk).
4. Esc ends the preflight; the preflight button shows the issue count (preflight.spec).
5. Auto height / auto fit shortcuts (web ⌥⌘H / ⌥⌘C clash with Hide Others / Copy Style on the Mac: use ⌃⌥⌘H / ⌃⌥⌘C).
6. Double click on an edge or corner of a text frame fits it to its text (text.spec).
7. Page overview: arrow keys select a page, ⌥ arrow moves it (keyboard.spec).
8. Command palette also finds layers, pages, text styles and swatches; a swatch fills the selection (palette.spec).
9. A shortcut given to a command frees it from the command that had it (settings.spec).
10. Settings: layers panel shows the current page or the whole spread, a heading per page;
    the layers heading names the page shown (settings.spec, layers.spec).
11. Quick bar: aligns the layers inside a selected group or auto layout; font and type options
    above a text; W/H sizing in an auto layout (quick.spec, align.spec).
12. Arrange section: flatten and add auto layout buttons (align.spec).
13. A selected layer that a mask hides is still dragged where it is hidden (canvas.spec).
14. Hovering a text frame's in-port shows the frame it comes from (thread.spec).
15. Integer fields have minus and plus buttons (field.spec).
16. ⌘ + scroll over the quick bar zooms the canvas (canvas.spec).

## Progress
(updated as gaps are fixed; see git log "mac: parity …")
- fixed 1–7: Option align keys, Object ▸ Boolean with ⌥⌘U/S/I/X, F2 rename (Editor.renaming), Esc ends the
  preflight once nothing is selected, preflight button counts issues, ⌃⌥⌘C fit / ⌃⌥⌘H auto height,
  double click on a text frame's edge or corner fits it, overview arrows and ⌥ arrows. UI test KeysTests.
- fixed 8–9: palette finds layers, pages, swatches (fill the selection, else "Select a layer first") and text
  styles; a shortcut given to a command takes it from the command that had it. UI tests in PaletteTests.
- fixed 10: setting "Layers panel shows" current page / current spread (a disclosure per page), heading "Layers · Page N". UI test LayersPanelTests.
- fixed 11–12: quick bar aligns inside a group / auto layout, W/H sizing, font menu and type options above a text; arrange section has flatten and add auto layout. UI test QuickBarTests.
