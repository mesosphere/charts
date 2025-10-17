# Devbox Setup Guide

## Prerequisites
- macOS (Darwin) or Linux
- Nix package manager

## Installation

### 1. Install Devbox
```bash
curl -fsSL https://get.jetpack.io/devbox | bash
```

### 2. Initialize Devbox Environment
```bash
cd /Users/raj.surve/DKP/charts
devbox shell
```

### 3. Verify Tools
```bash
helm version
ct version
yamllint --version
yamale --version
kubectl version --client
kind version
```

## Usage

### Start Development Shell
```bash
devbox shell
```

### Run Linting
```bash
devbox run lint
# or
make ct.lint
```

### Run Tests
```bash
devbox run test
# or
make ct.test
```

## Troubleshooting

### Issue: Package not found on Apple Silicon
- Use Homebrew as fallback for helm and chart-testing
- Keep yamllint, yamale, kubectl, kind in devbox

### Issue: Version conflicts with asdf
- devbox and asdf can coexist
- devbox takes precedence in devbox shell
- asdf is used outside devbox shell
