# App icon

The selected artwork is the slate-blue folded-notebook-page dove on a warm white background. The left tail forms a notebook page with a margin and two ruled lines. The built-in image_gen tool produced the color variant during design exploration. The selected image was resized to a 1024 × 1024 opaque PNG for Xcode.

The project asset is `NotesApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`. Both app build configurations select `AppIcon`. The asset catalog supplies the native iPad icon renditions.

## Generation prompt

```text
Use case: precise-object-edit. Produce one color variant of this exact folded-notebook-page dove app icon. Variant color is Azul pizarra. Preserve the exact central silhouette, size, position, paper fold geometry, rectangular notebook-page tail, vertical margin and exactly two horizontal lines, head and raised wing of the reference. Recolor ALL of the green paper to Azul pizarra paper, broad main faces approximately #819BB5, restrained highlights #B6C7D7, folded shadows #4E6984 and the notebook margin/rules #465F77. Keep the opaque warm white background #FAF8F2, same soft contact shadow, same quiet premium minimal craftsmanship and same spacious composition. The whole dove and notebook tail should be clearly legible at small app-icon sizes. Use restrained dimensional folded-paper shading and crisp gentle edges. Only change the paper's palette, preserving its unified continuous sheet-to-bird construction. Single full-bleed opaque square icon only. No text, color names, lettering, palette swatches, notification marks, pencils, new objects, borders, rounded corner mask, collage or board.
```

## Verification

The asset is a square 1024 × 1024 PNG with no alpha channel. Xcode selects the AppIcon asset in both Debug and Release configurations. The Release and simulator builds succeeded. The updated icon was visually checked on the simulator Home Screen. The signed Release app was installed over the existing app on the connected iPad with CoreDevice installation sequence 2612.
