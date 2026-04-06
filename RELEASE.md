# How to Release Last Epoch Building

## Prerequisites

- Push access to the `dev` branch
- GitHub Actions enabled on the repository
- `APP_ID` and `PRIVATE_KEY` secrets configured in repository settings

## Choosing a Version Number

LEB follows [Semantic Versioning](https://semver.org/):
- **patch** (0.x.Y) — bug fixes, small improvements
- **minor** (0.X.0) — new features
- **major** (X.0.0) — breaking changes or major milestones

Current version is shown in `manifest.xml`.

## Release Steps

1. Make sure all changes are merged into `dev` and tested
2. Go to [Actions → Release next version](../../actions/workflows/release.yml)
3. Click **Run workflow**
   - Branch: `dev`
   - Version: enter number (e.g. `0.11.0`) or `patch` / `minor`
4. The workflow will automatically:
   - Compile all Lua files to bytecode
   - Update version numbers in `manifest.xml` and `changelog.txt`
   - Generate release notes from commit history
   - Create a release PR for review
5. Review the PR, edit release notes as needed
6. Merge the PR into `master`
7. The release is published automatically

## Updating Game Data (New LE Patch)

When Last Epoch releases a patch:

1. Update skill tree data in `src/TreeData/`
2. Update `src/GameVersions.lua` — add new version to `treeVersionList`
3. Update item/affix data in `src/Data/`
4. Rebuild ModCache: launch the app with `Ctrl` held to force rebuild
5. Run tests: `busted --lua=luajit`
6. Merge to `dev`, then release normally

## Installer and Portable

The `installer.yml` workflow builds both:
- An installable `.exe` setup
- A portable zip (extract and run — no installation needed)
