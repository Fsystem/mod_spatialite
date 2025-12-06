# mod_spatialite Builds

Pre-built mod_spatialite binaries for use with SQLite extensions. These builds bundle all required dependencies for standalone use.

## Supported Platforms

| Platform | Architecture | Status |
|----------|--------------|--------|
| Windows | x64 | Official binaries from gaia-gis.it |
| Windows | x86 | Official binaries from gaia-gis.it |
| macOS | x64 (Intel) | Built from Homebrew |
| macOS | arm64 (Apple Silicon) | Built from Homebrew |
| Linux | x64 | Built from apt packages |
| Linux | arm64 | Built from apt packages |

## Downloads

Download the latest release from the [Releases] page.

## Version

Current version: **5.1.0**

## Usage

### Loading in SQLite

```sql
SELECT load_extension('/path/to/mod_spatialite');
```

### With better-sqlite3 (Node.js)

```javascript
const Database = require('better-sqlite3');
const db = new Database('mydb.sqlite');
db.loadExtension('/path/to/mod_spatialite');
```

## Dependencies Bundled

Each platform bundle includes all required dependencies:

- libgeos (Geometry Engine)
- libproj (Coordinate transformation)
- libfreexl (Excel file reading)
- librttopo (RT Topology Library)
- libxml2 (XML parsing)
- zlib (Compression)

## Building

Builds are automated via GitHub Actions. To trigger a new build:

1. Create a new release tag (e.g., `v5.1.0`)
2. GitHub Actions will build for all platforms
3. Binaries are attached to the release

## Manual Build

To build locally (macOS/Linux only - Windows uses official binaries):

```bash
# macOS (requires: brew install libspatialite)
./scripts/bundle-macos.sh arm64  # or x64 for Intel

# Linux (requires: apt install libsqlite3-mod-spatialite patchelf)
./scripts/bundle-linux.sh x64  # or arm64
```

For Windows, download official binaries directly from [gaia-gis.it](http://www.gaia-gis.it/gaia-sins/).

## License

mod_spatialite is licensed under the MPL tri-license (MPL 1.1/GPL 2.0+/LGPL 2.1+).
See https://www.gaia-gis.it/fossil/libspatialite/index for details.

## Credits

- [SpatiaLite](https://www.gaia-gis.it/fossil/libspatialite/index) - The SpatiaLite project
- [Homebrew](https://brew.sh/) - macOS package manager
- [gaia-gis.it](http://www.gaia-gis.it/) - Official SpatiaLite binaries
