# Translate That

Translate and fix your writing from the menu bar.

Press ⌃⌘T in any app and a small window opens with the text you had selected, already translated by Google Translate. Send the result back into the app you came from with one key. If Claude Code or Codex is set up on your Mac, switch it on in Settings for more natural translations and a mode that fixes grammar.

**[Download the installer](https://github.com/home-app-labs/translate-that/releases/latest/download/Translate-That.pkg)** · [Website](https://homeapplabs.com/translate-that/) · macOS 14 or later · free

## What it does

- **One shortcut, any app.** ⌃⌘T opens the window in the middle of the screen, on top of whatever you are doing. Selected text is picked up and translated straight away. You choose the shortcut in Settings.
- **Lives in the menu bar.** No Dock icon. A click on the menu bar icon opens the same window under the icon.
- **Translates as you type.** Google Translate answers while you write and shows the language it detected.
- **Any direction.** The source language is detected, or you choose it. One button swaps the two languages and translates the result back.
- **Edit the result.** The lower field is editable. The arrow button moves the result up to translate it again, for example into a third language.
- **Copy or insert.** Copy puts the result on the clipboard and closes the window. Insert pastes it into the app you came from, over the selection.
- **An AI assistant, if you have one.** The window always lists Google, Claude and ChatGPT. Google works from the start. Choosing Claude or ChatGPT while it is off explains what it needs and takes you to Settings. Translate That finds Claude Code and Codex on your Mac and can use the one you are already signed in to. With it on, the window gains another engine and an Improve mode that corrects grammar, spelling and awkward phrasing without changing what you said.

## Keys

| Key | Action |
| --- | --- |
| ⌃⌘T | Open with the selected text, or close. Change it in Settings |
| ⇧⌘C | Copy the result and close |
| ⇧⌘↩ | Insert the result into the app you came from |
| ⌘P | Pin: keep the window open when you click elsewhere |
| ⌘, | Settings |
| Esc | Close |

With an assistant switched on:

| Key | Action |
| --- | --- |
| ⌘1, ⌘2 | Translate, Improve |
| ⌘G | Switch to the next engine: Google, Claude, ChatGPT |
| ⌘↩ | Run |
| Esc | Stop the assistant, or close |

## Settings

The gear in the window, or a right-click on the menu bar icon.

- **Shortcut.** Click the shortcut and press the keys you want. If another app already holds them, the old shortcut stays.
- **Launch at login.**
- **AI assistants.** Shows whether Claude Code and Codex were found on this Mac, with a switch for each and the Claude model.

## Where your text goes

Translation needs a service, so this is the one Home App Labs app that uses the network. Nothing is sent until there is text in the window.

| Engine | Where the text is sent |
| --- | --- |
| Google | `translate.googleapis.com`, the keyless address used by Google's own web widgets. It is not an official API and may stop answering |
| Claude, only when switched on | Anthropic, through the Claude Code program on your Mac |
| ChatGPT, only when switched on | OpenAI, through the Codex program on your Mac |

Google receives the text while you type, and the text selected when you press the shortcut. Do not use the app for text that must not reach Google, or switch an assistant on and select it before pasting.

Nothing is written to disk except your settings.

## Using an AI assistant

Translate That has no account, key or server of its own. If one of these command-line programs is set up on your Mac, it can start that program and let it answer:

| Assistant | Program | Sign in once with |
| --- | --- | --- |
| Claude | [Claude Code](https://claude.com/claude-code) | `claude` in Terminal |
| ChatGPT | [Codex](https://developers.openai.com/codex) | `codex` in Terminal |

What that means:

- The program is already signed in as you. Translate That never sees your password or token.
- Requests count against your own plan with that company, and the text is sent to that company.
- Both are off until you switch them on in Settings. Settings shows whether each program was found.
- Claude runs with tools, MCP servers, settings and session history switched off: plain text in, plain text out. The model is chosen in Settings: Haiku, Sonnet (the default) or Opus.
- Codex runs in its read-only sandbox, in an empty folder, ignoring your Codex configuration and saving no session. Its answer arrives whole rather than word by word.

ChatGPT through Codex is experimental: it was built from the Codex documentation and has not been tried with many setups yet. Please report what you find.

Whether your plan allows this kind of use is between you and the company that runs the assistant. Check their terms if you are unsure.

If a program is missing, Settings says so and Google keeps working.

## Install

1. Download [Translate-That.pkg](https://github.com/home-app-labs/translate-that/releases/latest/download/Translate-That.pkg) and open it.
2. The app is not signed with a paid Apple developer certificate, so macOS blocks the installer the first time. Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.
3. Follow the installer. It copies Translate That to your Applications folder and opens it.

There is a step by step guide with pictures on the [website](https://homeapplabs.com/install/).
Prefer to move the app yourself? Take `Translate-That.zip` from the [latest release](https://github.com/home-app-labs/translate-that/releases/latest).

## Permissions

- **Accessibility** lets the app read the text you selected when you press ⌃⌘T, and paste the result when you choose Insert. Allow it from the menu bar menu. Without it the window opens empty and Insert only copies.
- Some apps do not share their selection through Accessibility. Copy the text and paste it into the window instead.
- **⌃⌘T** may already be taken by another app. Settings and the menu say so when that happens; pick another shortcut there.

## Build from source

You need Xcode 15 or later.

    git clone https://github.com/home-app-labs/translate-that.git
    cd translate-that
    ./build.sh --install --run

`./build.sh` assembles `build/Translate That.app`, `--install` copies it to `/Applications`, `--run` opens it. Run the tests with `swift test`.

The app is signed ad hoc, so macOS forgets the Accessibility permission after every rebuild: remove Translate That from the list and add it again. If you have a signing certificate, `TRANSLATEPLUS_SIGN_IDENTITY="..." ./build.sh` keeps the permission.

## Layout

| Path | What is there |
| --- | --- |
| `Sources/TranslatePlus/Engines.swift` | Languages, prompts, Google Translate, running Claude Code and Codex |
| `Sources/TranslatePlus/TranslatorModel.swift` | The window's state, starting and cancelling requests, saved choices |
| `Sources/TranslatePlus/TranslatorPanel.swift` | The window, its keys, Copy and Insert |
| `Sources/TranslatePlus/PanelView.swift` | The window's interface and the settings page |
| `Sources/TranslatePlus/FrontApp.swift` | Reading the selection and pasting into the app in front |
| `Sources/TranslatePlus/HotKey.swift` | The system-wide shortcut: registering, recording, naming |
| `Sources/TranslatePlus/TranslatePlusApp.swift` | Launch, the menu bar icon and menu, development aids |
| `Tests` | Unit tests for reading Google, Claude and Codex answers and naming shortcuts |
| `Resources` | Info.plist and the icon |
| `scripts` | Icon drawing and the release script |

The app was first called Translate Plus. The code and the bundle identifier `local.translateplus` keep that name so that existing settings carry over.

## Where your data lives

| What | Where |
| --- | --- |
| Settings | the `local.translateplus` defaults domain |

There is no history and no data folder.

## Development aids

Environment variables that make the app easier to test. Run the built binary directly, for example `TRANSLATEPLUS_SNAPSHOT_DIR=/tmp/shot .build/debug/TranslatePlus`.

| Variable | Effect |
| --- | --- |
| `TRANSLATEPLUS_SNAPSHOT_DIR=/path` | Open the window, save `panel.png` and `info.txt` there and quit. Saved settings are not changed and the shortcut is not registered |
| `TRANSLATEPLUS_SHOW=settings` | Open the settings page instead of the translator |
| `TRANSLATEPLUS_DEMO_CLAUDE=1`, `TRANSLATEPLUS_DEMO_CODEX=1` | Switch the assistants on for the snapshot |
| `TRANSLATEPLUS_CLAUDE_PATH=/path`, `TRANSLATEPLUS_CODEX_PATH=/path` | Use a stand-in program instead of the real one |
| `TRANSLATEPLUS_SNAPSHOT_DELAY=8` | Wait that many seconds before the snapshot (default 6) |
| `TRANSLATEPLUS_DEMO_TEXT=text` | Fill the input and run it |
| `TRANSLATEPLUS_DEMO_MODE=translate` or `improve` | Pick the mode |
| `TRANSLATEPLUS_DEMO_ENGINE=google`, `claude` or `codex` | Pick the engine |
| `TRANSLATEPLUS_DEMO_CHOOSE=claude` or `codex` | Click that engine in the window, switched on or not |

## Releasing

1. Put the new version number into `VERSION` and describe the changes in `release-notes/<version>.md`.
2. Commit.
3. Run `./scripts/release.sh --publish`. It builds a universal app, the installer and the zip, tags the commit and creates the GitHub release with the files attached.

The download links above always point at the latest release.

## Made with AI

Translate That is built by [Home App Labs](https://homeapplabs.com): one person with an idea, and an AI coding assistant doing the typing. Every line is here to read. Fork it and make it yours.

## License

[MIT](LICENSE)
