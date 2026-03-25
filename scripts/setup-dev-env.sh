#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${ROOT_DIR}/.venv"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required but was not found on PATH."
  exit 1
fi

if [[ ! -d "${VENV_DIR}" ]]; then
  echo "Creating virtual environment at ${VENV_DIR}..."
  python3 -m venv "${VENV_DIR}"
else
  echo "Virtual environment already exists at ${VENV_DIR}."
fi

echo "Activating virtual environment..."
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

echo "Upgrading pip..."
pip install --upgrade pip

echo "Installing development dependencies..."
pip install -r "${ROOT_DIR}/requirements.dev.txt"

echo
echo "Dev environment is ready."
echo "Activating virtual environment..."
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
