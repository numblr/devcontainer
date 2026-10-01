#!/usr/bin/env bash
set -euo pipefail

# Install a TeX Live subset providing pdflatex (and bibtex) so the manuscript
# in publication/ can be built. The package set covers what the manuscript
# actually uses: pgfplots/TikZ, natbib, cleveref, mathtools/bm, booktabs, and
# the recommended fonts.
#
# Idempotent: safe to re-run. Runs during postCreateCommand; uses sudo because
# the remoteUser (vscode) is not root but has passwordless sudo in the image.

if command -v pdflatex >/dev/null 2>&1; then
  echo "pdflatex already installed: $(pdflatex --version | head -n1)"
  exit 0
fi

echo "Installing TeX Live (pdflatex + manuscript packages)..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  texlive-latex-base \
  texlive-latex-recommended \
  texlive-latex-extra \
  texlive-fonts-recommended \
  texlive-science \
  texlive-pictures \
  texlive-bibtex-extra \
  biber
sudo rm -rf /var/lib/apt/lists/*

pdflatex --version | head -n1
echo "LaTeX install complete."
