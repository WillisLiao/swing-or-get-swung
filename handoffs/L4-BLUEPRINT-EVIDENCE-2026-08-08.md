# L4 Blueprint Evidence - 2026-08-08

This evidence records the latest blueprint-driven visual shell candidate and is explicitly not an L4 acceptance report.

## Reference sheets

- [Blueprint 1](</Users/willis/Documents/IOSapp/temp/map design/ChatGPT Image 2026年8月8日 下午08_12_25 (1).png>)
- [Blueprint 2](</Users/willis/Documents/IOSapp/temp/map design/ChatGPT Image 2026年8月8日 下午08_12_26 (2).png>)
- [Blueprint 3](</Users/willis/Documents/IOSapp/temp/map design/ChatGPT Image 2026年8月8日 下午08_12_27 (3).png>)
- [Blueprint 4](</Users/willis/Documents/IOSapp/temp/map design/ChatGPT Image 2026年8月8日 下午08_12_27 (4).png>)
- [Blueprint 5](</Users/willis/Documents/IOSapp/temp/map design/ChatGPT Image 2026年8月8日 下午08_12_28 (5).png>)
- [Blueprint 6](</Users/willis/Documents/IOSapp/temp/map design/ChatGPT Image 2026年8月8日 下午08_12_28 (6).png>)
- [Blueprint 7](</Users/willis/Documents/IOSapp/temp/map design/ChatGPT Image 2026年8月8日 下午08_12_29 (7).png>)
- [Blueprint 8](</Users/willis/Documents/IOSapp/temp/map design/ChatGPT Image 2026年8月8日 下午08_12_29 (8).png>)

## Current live capture set

The latest matching Godot MCP capture run is `r22959500-38` from `res://scenes/concourse_v2_art_preview.tscn`.

The captured views are `overview_oblique`, `overview_top`, `north_player`, `east_player`, `south_player`, `west_player`, `center_player`, and `elevated`.

The top-down view used a temporary diagnostic camera pose and emitted one colinear `look_at` warning; no project source warning or runtime error was introduced.

The source scene and asset used for the captures are [concourse_v2_art_preview.tscn](/Users/willis/Documents/IOSapp/scenes/concourse_v2_art_preview.tscn), [concourse_v2_visual.tscn](/Users/willis/Documents/IOSapp/scenes/concourse_v2_visual.tscn), and [concourse_v2_environment.glb](/Users/willis/Documents/IOSapp/assets/maps/concourse_v2_environment.glb).

The screenshots are live MCP image captures shown in the task transcript rather than separately persisted PNG files.

## Sol XHigh preflight matrix

The read-only `gpt-5.6-sol` XHigh review found the original candidate visually failed circular readability, four-way organization, primary and secondary lanes, elevated ring continuity, vertical access, bases, reactor visibility, cover clusters, outer wall architecture, infrastructure, floor segmentation, hazard language, signage, materials, and lighting.

Sol found neutral faction treatment narrowly passed because the role names were import-contract names and the authored albedos were mirrored neutral values rather than red or blue team colors.

Sol identified three real design tensions but no required escalation: elevated ring visibility versus frozen routes, reactor visibility versus frozen occluders, and literal blueprint texture and lighting references versus the shadowless and texture-free constraints.

Sol prioritized visibility, a taller open reactor, clearer lane hierarchy, gateway silhouettes, low-poly modular skinning, elevated rails and access, neutral material hierarchy, and sparse signage.

## Terra review summaries

The first Terra review after the initial visual correction returned `SPECIFIC FROZEN-CONTRACT CONFLICT` because opaque frozen wall and route occlusion prevented recognizable player-height correspondence even though the overview improved.

The second Terra review after the 9,124-triangle gateway, reactor, ring, signage, and cover correction returned `NOT FAITHFUL`, passing the circular shell and reactor but failing the strong four-way lanes, cover rhythm, continuous ring, gateway silhouettes, material language, and amber/lime hierarchy.

The third Terra review after the 12,340-triangle radial density correction returned `NOT FAITHFUL`, passing the circular shell, central open reactor, neutral treatment, route markers, radial movement, and shadowless readability while failing the industrial surface language and strong gateway landmarks.

The latest Terra review after the 15,364-triangle panel, ring, stair, and color correction returned `NOT FAITHFUL`.

The latest Terra review passes circular shell, four-way radial hierarchy, tall open reactor, neutral treatment, shadowless readability, and a visibly continuous elevated ring with access connections.

The latest Terra review fails the low/high cover silhouettes, heavy gateway and numeral landmark strength, modular panel/trim/grate/conduit language, and amber maintenance hierarchy.

The latest Terra review explicitly found no frozen-contract conflict and says the remaining gaps are fixable visual deficiencies.

## Latest measured candidate

Blender MCP confirms exactly eight mesh objects, no non-mesh objects, one material slot per role, and 15,364 authored triangles.

The imported GLB is 834,204 bytes, which is below the 3 MiB limit.

The expected imported bounds are `AABB(Vector3(-60.0, -1.0, -60.0), Vector3(120.0, 8.2, 120.0))`.

The runtime wrapper still uses six cached clean material variants, mirrored neutral identity colors, mirrored amber indicator colors, a lime neutral reactor, no textures, no procedural grime, no AO, no shadows, and no extra viewports.

The frozen gameplay collision, 129-solid map, routes, scale, and gameplay scene were not changed during the visual shell corrections.

## Validation

Fresh headless import passed after the latest export.

The visual exercise and all 19 `tools/*_exercise.gd` scripts passed after the latest export.

The headless 4v4 CPU sample reported `frames=120 avg_ms=16.67 min_ms=16.67 max_ms=16.67`; the runner returned watchdog status 124 after printing the complete sample, and headless mode does not measure mobile GPU cost.

The live Godot MCP preview monitor reported 328 draw calls, 24,917 primitives, 145 FPS, and approximately 0.000080 seconds of physics processing.

The 328 draw-call result is above the frozen 320 hard ceiling and remains an explicit unresolved performance failure.

No on-device iPhone or iPad thermal, battery, GPU, or long-session verification was performed.

## Next correction target

The next pass should spend remaining visual budget on distinctive gateway silhouettes and numeral panels, varied cover profiles, readable grate and conduit bands, and a stronger amber maintenance system while preserving the current macro layout and all frozen contracts.
