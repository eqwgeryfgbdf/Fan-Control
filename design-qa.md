# Design QA

Date: 2026-10-23. Scope: native monitoring window and shared quick-control panel, light appearance, authorization deferred by the user.

## Evidence and normalization

- Source visual truth: `docs/selected-design.png` (1487 × 1058 pixels), selected option 3. Includes desktop framing and a menu bar popover, demonstration values, manual selection with an unapplied 2,000 RPM target.
- Implementation: `docs/main-window.png` (1100 × 760 pixels), native window at normal size; `docs/control-panel-manual.png` (1920 × 980 pixels), zoomed native window so the full toolbar popover is captured; `docs/control-panel.png` captures its automatic state.
- Native AppKit/SwiftUI screenshots, not a browser; CSS size and deviceScaleFactor are not applicable. Screenshots are 1 pixel per captured logical point. The generated reference has no declared logical-point density.
- All three source/main/manual images were opened together in one comparison input. The main window content, excluding wallpaper and system menu chrome, was assessed for relative proportions. This is a joint-image comparison, not a pixel-exact overlay or a same-viewport side-by-side screenshot.
- Focused comparison: the source's upper-right control panel and the actual screenshot's rightmost 380-point panel were inspected together for RPM/temperature rows, control grouping, target/range, actions and footer. Full-resolution images retain readable labels.
- State differences: actual values are live, and controls are disabled because the user deferred authorization. The captured panel is anchored to the toolbar; the menu bar uses the same `MenuPanel` view, but its menu bar anchor was not captured. A regular Liquid Glass control surface was added at the user's explicit request after choosing option 3.

## Findings and fidelity surfaces

No remaining actionable P0/P1/P2 visual findings in the captured states.

- Fonts/typography: native system font and monospaced numbers preserve a clear title → reading → supporting text hierarchy. Standard macOS control sizes are intentionally smaller than the generated mock's enlarged labels. No observed truncation or wrapping collision.
- Spacing/layout: chart-first structure, hardware table, generous margins and compact upper-right controls match the selected direction. Normal and zoomed windows retain all primary regions. Native toolbar, traffic lights, segmented controls and popover geometry are intentionally platform-standard.
- Colors/tokens: white/light content, blue chart and selected controls, secondary gray metadata and separators remain consistent. Custom glass is restricted to the interactive control group; charts and table remain plain. The native popover's system material remains readable over live content.
- Image/assets: SF Symbols provide crisp native fan, CPU, thermometer and gear icons. No decorative bitmap from the reference is replaced with drawn approximations. The independently generated application icon is packaged as an icns asset, not used in place of data or navigation.
- Copy/content: requested app name is retained, labels use Traditional Chinese, mock-only demonstration labels are removed, and CPU/GPU averages are explicit. Actual and target RPM are distinct; “未套用” and disabled actions accurately describe the pending state. Permission copy is necessary for operating the native helper.

## Comparison history

Earlier implementation review identified a gray content canvas that weakened the selected clean white composition and an SDK metadata issue that prevented the intended modern native appearance. The content background was changed to the system text-background color and the build now records SDK 27 with minimum OS 15. The current `main-window.png` and `control-panel-manual.png` are post-fix captures reviewed jointly with the selected reference. Earlier temporary captures were superseded, so no pixel-difference claim is made.

The authorization state initially hid manual-selection controls. The final UI keeps mode selection and bounded target preview visible, with Apply disabled until permission is available. The post-fix manual screenshot and accessibility tree show 2,000 RPM, 1,000–4,900 RPM bounds, “未套用”, and disabled Apply/Restore.

## Interactions and remaining gaps

Verified in the native UI: time-range selection, pause/resume while readings continue, settings, automatic/manual preview selection, full control popover layout and unauthorized action gating. No browser console applies to this SwiftUI application.

Physical fan adjustment and recovery remain untested because the user explicitly deferred authorization. macOS 15 fallback, Intel runtime, dark appearance, Reduce Transparency and the status-item anchor require additional runtime/visual checks; they are not claimed as passed. These are documented verification gaps, not hidden substitutes for live testing.

## Implementation checklist

- [x] Preserve chart-first option 3 and native SF Symbols.
- [x] Keep real readings distinct from requested targets.
- [x] Limit version-gated Liquid Glass to controls.
- [x] Show a usable monitoring UI while authorization is deferred.
- [x] Compare source, normal window and complete control panel captures together.
- [ ] After user authorization, verify actual speed change and automatic restoration on this hardware.
- [ ] Verify additional OS/hardware/accessibility appearance combinations when available.

final result: passed
