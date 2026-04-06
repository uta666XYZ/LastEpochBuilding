# Contributing to Last Epoch Building

Feedback, bug reports, and contributions are always welcome!

## Table of Contents
1. [Reporting Bugs](#reporting-bugs)
2. [Requesting Features](#requesting-features)
3. [Contributing Code](#contributing-code)
4. [Setting Up a Development Environment](#setting-up-a-development-environment)
5. [Running Tests](#running-tests)

---

## Reporting Bugs

### Before submitting:
- Check that the bug hasn't already been reported in [Issues](../../issues)
- Make sure you are running the latest version

### When submitting:
- Select the appropriate issue template
- Include steps to reproduce the bug
- If it's a calculation issue, include your build (export via the Import/Export tab)

---

## Requesting Features

Feature requests are welcome. Please open an issue and describe:
- What you want to achieve
- Why it would be useful

---

## Contributing Code

### Before submitting a pull request:
- Pull requests must target the **`dev` branch**
- Test your changes before submitting
- Do not commit `src/Data/ModCache.lua` — this is auto-generated

### Pull request checklist:
- [ ] Targets `dev` branch
- [ ] Changes tested manually
- [ ] No auto-generated files committed unnecessarily

---

## Setting Up a Development Environment

1. Clone the repository:
   ```bash
   git clone -b dev https://github.com/uta666XYZ/LastEpochBuilding.git
   ```

2. Run the app from the repository:
   ```
   runtime\Last Epoch Building.exe
   ```
   Running from the repo automatically enables **Dev Mode**:
   - `F5` — restart in-place
   - `Ctrl + ~` — toggle console
   - `ConPrintf()` — print to console
   - Hold `Alt` — show debug info on tooltips

### Recommended: VS Code with EmmyLua

1. Install [EmmyLua](https://marketplace.visualstudio.com/items?itemName=tangzx.emmylua) extension
2. Configure Java path in settings if needed:
   ```json
   "emmylua.java.home": "C:/Program Files/Java/jre..."
   ```
3. To avoid memory issues, add `emmy.config.json` to `.vscode/`:
   ```json
   {
     "source": [{
       "dir": "../",
       "exclude": [
         "src/Export/**.lua",
         "src/Data/**.lua",
         "src/TreeData/**.lua"
       ]
     }]
   }
   ```

---

## Running Tests

LEB uses [Busted](https://olivinelabs.com/busted/) for Lua testing.

```bash
# Install
luarocks install busted

# Run tests
busted --lua=luajit
```

### Adding test builds:
1. Add build XML to `spec/TestBuilds/1.4/`
2. Run `busted --lua=luajit -r generate` to generate expected output
3. Run `busted --lua=luajit` to verify

---

## Documentation

- [How mods are parsed](docs/addingMods.md)
- [Mod syntax reference](docs/modSyntax.md)
- [How skills work](docs/addingSkills.md)
