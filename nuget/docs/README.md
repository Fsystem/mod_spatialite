# Spatialite.Native

Pre-built mod_spatialite native libraries for SQLite spatial extensions.

## Supported Platforms

| Platform | Architecture | Runtime Identifier |
|----------|--------------|-------------------|
| Windows | x64 | win-x64 |
| Windows | x86 | win-x86 |
| macOS | x64 (Intel) | osx-x64 |
| macOS | arm64 (Apple Silicon) | osx-arm64 |
| Linux | x64 | linux-x64 |
| Linux | arm64 | linux-arm64 |

## Usage

After installing this NuGet package, the native libraries for all supported platforms will be automatically copied to your output directory under the `runtimes/{rid}/native/` folder structure.

### Loading in .NET

```csharp
using Microsoft.Data.Sqlite;

var connection = new SqliteConnection("Data Source=mydb.sqlite");
connection.Open();
connection.LoadExtension("mod_spatialite");
```

### Loading with SQLitePCLRaw

```csharp
using SQLitePCL;

raw.SetProvider(new SQLite3Provider_e_sqlite3());
// Then load the extension
```

## Dependencies Bundled

Each platform bundle includes all required dependencies:

- libgeos (Geometry Engine)
- libproj (Coordinate transformation)
- libfreexl (Excel file reading)
- librttopo (RT Topology Library)
- libxml2 (XML parsing)
- zlib (Compression)

## License

mod_spatialite is licensed under the MPL tri-license (MPL 1.1/GPL 2.0+/LGPL 2.1+).
See https://www.gaia-gis.it/fossil/libspatialite/index for details.
