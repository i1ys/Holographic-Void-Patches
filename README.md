# Holographic Void 2

Fixing holographic void so it becomes an actually reliable theme that's pretty and has good qol :v:

## overall todo:
- remove excess features
- restructure everything so it's actually maintainable
- fix logic in code

## Colors

Copy `colorConfig.example.lua` to `Save/Holographic Void 2_settings/colorConfig.lua`
inside Etterna. Create the settings directory if needed. Edit the file and reload
the theme or restart Etterna. A missing or invalid field uses the selected
palette's default color. An accent link takes priority over that element's hex
override.

If you already customized colors in HV2, your old HV2 settings supply the colors
until you create `colorConfig.lua`. Copy any values you want to keep into the new
file before reloading. In `themeConfig.lua`, `HV_AccentColor` becomes `accent`,
`HV_MSDColorScaleV3` becomes `msdScale`, and the color-style fields move under
`palettes`. In the old custom colors file, the color groups move under
`overrides` and `__syncToAccent` becomes `syncToAccent`. HV2 never rewrites
`colorConfig.lua`.
