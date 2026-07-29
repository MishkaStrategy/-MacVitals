# Application Icon

MacVitals ships with a project-owned application icon. It uses a dark rounded-square diagnostic panel and a high-contrast pulse trace. The artwork contains no third-party logos, fonts or downloaded assets.

## Reproducible source

The canonical artwork, rasterizer, PNG encoder and ICNS packager are implemented in:

- `scripts/materialize_app_icon.py`

No binary or encoded image source is stored in the repository. The generator uses only the Python standard library and produces every required representation deterministically.

The reviewed generated ICNS SHA-256 is recorded in the generator and checked on every build.

The generated `MacVitals/Resources/AppIcon.icns` file is intentionally ignored by Git. Materialize it before generating the Xcode project:

```bash
python3 scripts/materialize_app_icon.py
xcodegen generate
```

`make bootstrap`, all macOS workflows and the packaging script perform this step automatically.

## Validation

The generator verifies:

- the reviewed generated SHA-256;
- the ICNS header and total length;
- exactly one required chunk for 16, 32, 64, 128, 256, 512 and 1024 pixel representations;
- embedded PNG structure, dimensions, encoding flags and CRC values;
- byte-for-byte equality between the packaged icon and freshly generated data.

Run the portable checks without writing generated files:

```bash
python3 scripts/materialize_app_icon.py --self-test
python3 scripts/materialize_app_icon.py --check-only
```

Release verification also requires `CFBundleIconFile=AppIcon.icns`, rejects encoded source files inside the app bundle, and compares the ZIP and DMG icon payloads.

## Updating the artwork

An icon update must be reviewed visually at every representation size, update the deterministic geometry or palette in `materialize_app_icon.py`, update its reviewed SHA-256 constant, and pass the complete local and macOS release gates. Generated `AppIcon.icns` files must not be committed directly.
