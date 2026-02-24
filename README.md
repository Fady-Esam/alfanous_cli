# 🌙 Alfanous Core CLI

A standalone, pure Dart CLI library for the **Alfanous** offline Quran search engine. 

This repository serves as the **barebone core engine**, completely decoupled from any UI framework (Zero-Flutter). Inspired by the `libvlc` architectural paradigm, it acts as a low-level, UI-agnostic backend that can be consumed by any Dart frontend (Mobile, Web, Desktop) or compiled into a standalone native binary.

## ✨ Core Architecture & Features
* **Pure Dart & FFI:** Built using the pure Dart `sqlite3` FFI package for maximum performance and strict memory management.
* **Isolated NLP Engine:** Includes the complete Arabic text normalization, diacritic stripping, and stop-word filtering algorithms.
* **Advanced Query Parser:** Supports complex search operators translated directly into strictly optimized SQLite FTS5 queries
* **Testable in Isolation:** Fully decoupled from UI elements, making it 100% unit-testable.

## 🚀 Getting Started

### Prerequisites
* Dart SDK
* `quran.db` file placed in the root directory.

### Installation & Setup
1. Clone the repository:
   ```bash
   git clone [https://github.com/Fady-Esam/alfanous_cli.git]
   cd alfanous_cli

2. Get dependencies:
```bash
  dart pub get
```
## 💻 Usage (CLI)
You can run the engine directly from the terminal to test the search logic in isolation:
```bash
dart run bin/alfanous.dart search --query "الجنة" --limit 5
```
## 📦 Compiling to a Native Binary
To compile this core library into a standalone executable (similar to a C++ or Rust binary) that can run on any machine without the Dart SDK:

dart compile exe bin/alfanous.dart -o alfanous_core.exe
Then run the generated binary:
```bash
./alfanous_core.exe search --query "الله"
```
