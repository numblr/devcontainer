#!/usr/bin/env bash
set -euo pipefail

# Install a TeX Live subset providing pdflatex (and bibtex/biber). The package
# set covers what the manuscripts actually use: pgfplots/TikZ, natbib, cleveref,
# mathtools/bm, booktabs, and the recommended fonts.
#
# Runs as ROOT at image build time, so no sudo and the ~2GB result lands in a
# cached image layer instead of being reinstalled on every container create.
#
# Idempotent: safe to re-run.

if command -v pdflatex >/dev/null 2>&1; then
  echo "pdflatex already installed: $(pdflatex --version | head -n1)"
  exit 0
fi

echo "Installing TeX Live (pdflatex + manuscript packages)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  texlive-latex-base \
  texlive-latex-recommended \
  texlive-latex-extra \
  texlive-fonts-recommended \
  texlive-science \
  texlive-pictures \
  texlive-bibtex-extra \
  biber
rm -rf /var/lib/apt/lists/*

pdflatex --version | head -n1
echo "LaTeX install complete."
