# Center - Git Repository Menubar App

A macOS menubar application that displays all git repositories from a configurable directory with their current branches.

## Features

- **Repository Discovery**: Automatically scans a directory for git repositories
- **Branch Display**: Shows current branch for each repository
- **Configurable Directory**: Set custom directory path (defaults to ~/Developer)
- **Multiple Editor Support**: Open repositories in VS Code, Finder, or Terminal
- **Live Updates**: Refresh button to update repository list

## Installation

1. Clone this repository
2. Compile the app:
   ```bash
   swiftc -o CenterApp main.swift AppDelegate.swift -framework Cocoa
   ```
3. Run the app:
   ```bash
   ./CenterApp
   ```

## Usage

- Click the menubar icon to see all git repositories
- Click any repository to open it in your preferred editor
- Use "Preferences" to change the directory path or default editor
- Use "Refresh" to update the repository list

## Requirements

- macOS 10.15 or later
- Git installed in `/usr/bin/git`

## Configuration

The app stores preferences using UserDefaults:
- `developerDirectory`: Path to scan for repositories
- `defaultEditor`: Preferred editor (VS Code, Finder, or Terminal)