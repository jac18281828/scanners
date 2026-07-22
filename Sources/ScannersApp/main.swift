// Entry point. `ScannersAppRoot` (App.swift) can't be `@main` itself — a SwiftPM executable
// target can't mix an `@main`-attributed type with a file named `main.swift` in the same
// target — so this file just invokes it directly. Keeps `swift run ScannersApp` and
// `Scripts/run-dev.sh` working without any special-casing.
ScannersAppRoot.main()
