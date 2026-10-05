#!/usr/bin/env bash
set -e

source dev-container-features-test-lib

# --- toolchain binaries ---
check "pdflatex installed" bash -c "pdflatex --version | head -n1"
check "bibtex installed" bash -c "bibtex --version | head -n1"
check "biber installed" bash -c "biber --version | head -n1"

# --- package availability, order-independent ---
#
# kpsewhich asks TeX where a style file lives, without compiling anything. This
# is the check that actually answers "is the apt package list complete?", and it
# names the missing package directly. Doing it via a compiled document instead
# conflates a missing package with a document-authoring mistake -- inter-package
# load-order constraints (see below) made that distinction matter.
check "all expected .sty files are installed" bash -c '
  missing=""
  for p in tikz pgfplots natbib cleveref mathtools bm booktabs amsmath; do
    kpsewhich "$p.sty" >/dev/null || missing="$missing $p"
  done
  if [ -n "$missing" ]; then
    echo "missing style files:$missing"
    echo "adjust the apt package list in src/latex/install.sh"
    exit 1
  fi
  echo "all present"
'

# --- end-to-end compile ---
#
# Proves the toolchain actually produces a PDF, and exercises the packages
# rather than merely loading them (\Cref, \bm, \mathclap, booktabs rules, a
# pgfplots axis).
#
# The document is written with a QUOTED heredoc delimiter (<<'TEX'); an
# unquoted one makes bash process escapes in the body, silently turning the
# row terminator \\ into \ and breaking booktabs.
WORK="$(mktemp -d)"
cat > "$WORK/t.tex" <<'TEX'
\documentclass{article}
% Load order matters here, and getting it wrong is a hard error, not a warning:
% cleveref checks that amsmath is already loaded and aborts with
%   "! Package cleveref Error: cleveref must be loaded after amsmath!"
% otherwise. amsmath arrives via mathtools, so cleveref must come after it.
% Loading cleveref last is the general rule -- it patches cross-referencing and
% wants to see the other packages first.
\usepackage{tikz,pgfplots}
\usepackage{natbib}
\usepackage{mathtools,bm}
\usepackage{booktabs}
\usepackage{cleveref}
\pgfplotsset{compat=newest}
\begin{document}
\section{S}\label{sec:s}
\Cref{sec:s} $\bm{x}$ \( \mathclap{y} \)
\begin{tabular}{@{}l@{}}\toprule a\\ \bottomrule\end{tabular}
\begin{tikzpicture}\draw (0,0)--(1,1);\end{tikzpicture}
\begin{tikzpicture}\begin{axis}\addplot coordinates {(0,0) (1,1)};\end{axis}\end{tikzpicture}
\end{document}
TEX

# On failure, surface the LaTeX error. Swallowing it into /dev/null makes any
# problem look like an unexplained non-zero exit.
check "compiles a document to PDF" bash -c "
  cd '$WORK' || exit 1
  if ! pdflatex -interaction=nonstopmode -halt-on-error t.tex > build.log 2>&1; then
    echo '--- pdflatex failed; last 40 log lines ---'
    tail -n 40 build.log
    exit 1
  fi
  test -f t.pdf
"

reportResults
