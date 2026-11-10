# LabPBR materials and parallax mapping

This document describes the engine-side LabPBR work in this branch. It is not
a statement that every rendering backend or every material path has been
visually verified.

## Texture naming and loading

For a plain, static source image named `stone.png`, Luanti looks for sibling
material maps named:

- `stone_n.png`: LabPBR normal, ambient-occlusion, and height data.
- `stone_s.png`: LabPBR smoothness, reflectance/conductor, and emission data.

The base image and any companion map must have matching dimensions after the
mesh texture filter is applied. Missing maps are optional: the corresponding
shader feature is omitted, and the material retains its available rendering
path.

Animated images, texture modifier expressions, and composite texture
expressions are not assigned companion maps. A single sibling map cannot
describe the result of concatenating or transforming multiple source images.
Backends without fragment derivatives do not use the normal-map or POM path;
the specular map can still be used.

The normal and specular images are bound separately from the base-color
texture. This also works when the base image uses Luanti's 2D-array texture
path. The data-map mesh filter retains alpha because the normal-map alpha is
height and the specular-map alpha is emission. It still applies the configured
mesh upscaling and normal texture filtering.

## Decoded LabPBR channels

The current decoder uses these LabPBR channels:

| Map | Channel | Meaning |
| --- | --- | --- |
| Normal | R, G | Tangent-space X/Y normal, encoded in DirectX (Y-down) convention |
| Normal | B | Linear ambient visibility; 0 is occluded and 255 is unoccluded |
| Normal | A | Linear height; 0 represents the deepest point (up to 25% texture depth), 255 the surface |
| Specular | R | Perceptual smoothness, converted to roughness with `(1 - smoothness)^2` |
| Specular | G | Linear dielectric F0 for values 0–229 (directly `G / 255`); 230–255 identify conductors |
| Specular | A | Linear emission for values 0–254; 255 is the non-emissive sentinel |

The engine reconstructs normal Z from the encoded X/Y values and derives a
tangent frame from fragment position and texture-coordinate derivatives.
The normal map modulates natural-light diffuse response and the PBR specular
BRDF. Dynamic-shadow visibility attenuates the direct specular contribution;
the current shadow-map visibility test itself still uses geometric shadow data.
The specular branch uses a GGX microfacet distribution and Schlick Fresnel. Conductor IDs currently use an albedo-tinted F0 fallback;
the format's optional per-metal complex-IOR table is not implemented.

The LabPBR standard defines porosity/subsurface scattering in specular
blue as optional shader data; it is not currently shaded here. Predefined
complex-IOR constants for individual conductor IDs are also optional in the
implementation requirements; this renderer currently approximates all
conductors with albedo-tinted F0 instead. See the
[LabPBR material standard](https://shaderlabs.org/wiki/LabPBR_Material_Standard)
and [implementation requirements](https://shaderlabs.org/wiki/LabPBR_Implementation_Requirements)
for the required and optional channel scope.

This implementation also does not add an image-based-lighting or
environment-probe system; the direct specular contribution uses Luanti's
current sun/moon/custom shadow-light direction.

## Parallax occlusion mapping

POM is a separate, opt-in shader feature. When enabled and a normal map is
available, the fragment shader:

1. Builds a tangent frame from screen-space derivatives.
2. Transforms the view vector into tangent space.
3. Traverses the normal-map alpha height field using a bounded, configurable
   number of depth layers.
4. Interpolates between the samples around the first depth crossing.
5. Uses the displaced UV for base color and both material maps.

The maximum encoded LabPBR height depth is 25% of the texture depth. The
configured depth scale controls how much of that range is used. POM fades
toward grazing angles to limit excessive UV displacement. POM requires GLSL
1.30 or newer (desktop GL3) or GLSL ES 3.00 because its ray traversal uses
explicit texture gradients; normal mapping can remain enabled on older
derivative-capable programmable backends. POM is not applied when the normal
map is missing or the backend lacks the required shader language features.

## Settings

All settings are client-side:

| Setting | Default | Range / dependency |
| --- | --- | --- |
| `enable_pbr` | `false` | Enables optional normal and specular material maps |
| `enable_pbr_parallax` | `false` | Requires `enable_pbr` |
| `pbr_parallax_samples` | `24` | 8–64 samples |
| `pbr_parallax_height_scale` | `0.05` | 0.0–0.1 multiplier |

PBR remains disabled by default, preserving the non-PBR renderer unless the
client enables the feature. POM is independently disabled by default because
its per-fragment height traversal is more expensive than ordinary normal and
specular sampling.

## Tests and verification

The unit-test module `TestPBR` covers the companion-map resolver and the
LabPBR channel boundary conversions. It is compiled into the regular Luanti
unit-test target.

The Linux CI workflow includes a GL3 singleplayer smoke test that extracts a
dimension-matched stone base/normal/specular set from the repository's supplied
archive into the temporary CI checkout, enables PBR and POM in the client
configuration, and starts the existing Devtest game. This exercises the real
engine material path and shader startup, including the archive's normal-map
variants and missing-map fallback.

A separate POM visual-test script builds a deterministic Devtest stone room,
uses a generated non-flat RGBA LabPBR normal/height map so the visual assertion
does not depend on the supplied stone texture's height contrast, captures
matching POM-disabled and POM-enabled OpenGL frames, and compares the central
wall pixels. A measurable pixel difference is required; shader compilation by
itself does not count as visual verification.

The PBR asset-audit workflow inventories source image/map paths, checks
manifest targets and sidecar availability, and analyzes packed channel data.
Its report is a mapping audit, not a claim that every source image has a
corresponding Devtest material. The candidate mapping is
published in [the Devtest texture mapping manifest](devtest_texture_mapping.json).



## Supplied texture archive and redistribution

The supplied `Parallax PBR 64x v2.5.zip` is inventoried by CI. Its
`shaders/lib/brdf/labPBR.glsl` file contains a copyright notice pointing to
RRe36's Product License and Terms of Use:
https://rre36.com/copyright-license

That published license allows private modifications and certain media
showcases, but requires explicit permission to publicly redistribute the
product or parts of it, and to incorporate parts into another original
product. Therefore the source textures are not copied into Devtest or Windows
release packages. Obtain explicit permission from the author before adding
these textures to a distributable Luanti build. The mapping manifest records
candidate source names and missing matches without redistributing the artwork.

## Known limitations

- POM is currently integrated into the node shader path, not every possible
  entity, wield-item, formspec, or custom mesh shader.
- Animated and composite/modified texture expressions do not receive
  companion maps.
- Complex conductor optical constants and specular-blue porosity/SSS are not
  implemented.
- No environment-map reflections or global illumination are added by this work.
- The deterministic POM screenshot comparison is present, but must pass on the
  current branch head before POM can be marked visually verified.
