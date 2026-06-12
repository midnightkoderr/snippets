# Code snippets and scripts

This repository contains code snippets and scripts that I have found useful in my projects. They are organized by category and are intended to be easily accessible for reference and reuse.

## Categories

### Termux initialisation script

This script sets up a Termux environment with some useful packages and configurations. It can be run on a Termux installation to quickly get started with a functional terminal environment.

```bash
curl -fsSL https://raw.githubusercontent.com/midnightkoderr/snippets/main/termux/init.sh | bash
```

### Install llama.cpp

```bash
curl -fsSL https://raw.githubusercontent.com/midnightkoderr/llama.cpp-android-gpu/main/installer.sh | bash -s -- --install-dir ~/.local/bin --lib-dir ~/.local/lib

echo 'export LD_LIBRARY_PATH=${HOME}/.local/lib:${LD_LIBRARY_PATH}' >> ~/.bashrc

echo "Installation complete. Please add ~/.local/bin to your PATH and ~/.local/lib to your LD_LIBRARY_PATH if you haven't already."
```
