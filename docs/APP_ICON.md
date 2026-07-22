# Application Icon

MacVitals ships with a project-owned application icon. It uses a dark rounded-square diagnostic panel and a high-contrast pulse trace. The artwork contains no third-party logos, fonts or downloaded assets.

## Reproducible source

The canonical repository source is:

- `AssetsSource/AppIcon.icns.base64.part00` … `partNN`

The reviewed decoded ICNS SHA-256 is:

```text
ec94e8a136730d1bd133f6bd5d7418b050b3bdad3d06ff759b03e4c0fb39398e
```

The generated `MacVitals/Resources/AppIcon.icns` file is intentionally ignored by Git. Materialize it before generating the Xcode project:

```bash
python3 scripts/materialize_app_icon.py
xcodegen generate
```

`make bootstrap`, all macOS workflows and the packaging script perform this step automatically.

## Validation

The materializer uses only the Python standard library. It verifies:

- base64 integrity;
- the reviewed source SHA-256;
- contiguous source-part numbering;
- the ICNS header and total length;
- exactly one required chunk for 16, 32, 64, 128, 256, 512 and 1024 pixel representations;
- embedded PNG structure, dimensions, encoding flags and CRC values;
- byte-for-byte equality between the packaged icon and the reviewed source.

Run the portable checks without writing generated files:

```bash
python3 scripts/materialize_app_icon.py --self-test
python3 scripts/materialize_app_icon.py --check-only
```

Release verification also requires `CFBundleIconFile=AppIcon.icns`, rejects encoded source files inside the app bundle, and compares the ZIP and DMG icon payloads.

## Updating the artwork

An icon update must be reviewed visually at every representation size, replace the complete contiguous set of canonical encoded source parts, update the reviewed SHA-256 constant in `materialize_app_icon.py`, and pass the complete local and macOS release gates. Generated `AppIcon.icns` files must not be committed directly.
