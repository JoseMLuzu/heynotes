# App icon

The selected artwork is a white origami dove holding a prominent yellow pencil against a blue background. The pencil was enlarged and its yellow barrel and graphite tip strengthened for small-icon readability. The built-in image_gen tool produced this design during icon exploration. The selected image was resized to a 1024 × 1024 opaque PNG for Xcode.

The project asset is `NotesApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`. Both app build configurations select `AppIcon`. The asset catalog supplies the native iPad icon renditions.

## Generation prompt

```text
Use case: precise-object-edit. Asset type: one premium iPad handwritten-notes app icon concept. Edit the reference white origami dove on blue. Preserve its elegant paper-fold silhouette, white and very pale lavender materials, raised triangular wing, graceful head facing right, centered composition and soft dimensional shading. Remove both yellow notification marks above the head. Instead add ONE clearly recognizable small warm-yellow wooden pencil, delicately held by the dove's beak, integrated naturally into the composition. The pencil must have a simple yellow barrel, a visible sharpened pale wooden end and graphite writing point, broad clean shapes readable at small app-icon sizes. Keep the pencil secondary to the dove but large enough to identify at a glance, roughly one third of the icon's width, positioned on a gentle diagonal with breathing room around it. Use the warm yellow of the original marks as the pencil accent. Keep the background a softly luminous sky-blue to royal-blue gradient with a slightly calmer saturation than the reference. Minimal polished native Apple-style visual quality, restrained shadows, strong readable silhouette. Full-bleed opaque square artwork, one icon only, 1024 by 1024. Avoid extra pages, notebook, envelope, speech bubbles, motion trails, notification marks, lettering, text, borders, baked rounded corners, collage or presentation board.
```

## Pencil visibility refinement

```text
Use case: precise-object-edit. Improve ONLY the visibility of the pencil in this current iPad app icon. Preserve the exact existing white origami dove, its complete silhouette, folds, size, placement and white/pale-lavender paper shading, and preserve the original blue background. The dove must still naturally hold the pencil in its beak. Make the yellow pencil approximately 25 percent LONGER and 35 percent THICKER than the current one, with a more saturated warm golden-yellow barrel, a distinct pale wooden sharpened tip and a strong dark graphite writing point. Enlarge the muted pink eraser proportionately. Keep clean broad shapes that read unmistakably as a pencil at 60–80 pixel icon sizes. Adjust the pencil's position and angle only slightly around the existing beak contact point to keep its yellow barrel clearly visible against the blue backdrop, with a small amount of air between the barrel and the white neck. Keep the entire pencil within the icon's safe interior with ample margin from the edges. Preserve the visual balance and subtle premium dimensional style. One pencil only, no exaggerated cartoon details, no glow, no rays, no sparkles, no arrows, no lettering, no border, no additional objects, no rounded mask or mockup. Single opaque full-bleed square icon.
```

## Verification

The asset is a square 1024 × 1024 PNG with no alpha channel. Xcode selects the AppIcon asset in both Debug and Release configurations.

The signed Release and simulator builds succeeded. The updated icon was visually checked on the simulator Home Screen. The Release app was installed over the existing app on the connected iPad with CoreDevice installation sequence 2628.
