#!/usr/bin/env bash
set -e

source dev-container-features-test-lib

check "pdflatex installed" bash -c "pdflatex --version | head -n1"
check "bibtex installed" bash -c "bibtex --version | head -n1"
check "biber installed" bash -c "biber --version | head -n1"

# Compile a minimal document that loads every package this TeX Live subset
# exists to provide, so a missing .sty fails here rather than mid-manuscript.
#
# The document is written at top level with a QUOTED heredoc delimiter
# (<<'TEX'). An unquoted delimiter makes bash process escapes inside the body,
# which silently turns the row terminator \\ into \ and breaks booktabs.
WORK="$(mktemp -d)"
cat > "$WORK/t.tex" <<'TEX'
\documentclass{article}
\usepackage{tikz,pgfplots,natbib,cleveref,mathtools,bm,booktabs}
\pgfplotsset{compat=newest}
\begin{document}
\section{S}\label{sec:s}
\Cref{sec:s} $\bm{x}$ \( \mathclap{y} \)
\begin{tabular}{@{}l@{}}\toprule a\\ \bottomrule\end{tabular}
\begin{tikzpicture}\draw (0,0)--(1,1);\end{tikzpicture}
\begin{tikzpicture}\begin{axis}\addplot coordinates {(0,0) (1,1)};\end{axis}\end{tikzpicture}
\end{document}
TEX

# On failure, surface the LaTeX error. Swallowing it into /dev/null makes a
# missing package look like an unexplained non-zero exit.
check "compiles tikz/pgfplots/natbib/cleveref/mathtools/bm/booktabs" bash -c "
  cd '$WORK' || exit 1
  if ! pdflatex -interaction=nonstopmode -halt-on-error t.tex > build.log 2>&1; then
    echo '--- pdflatex failed; last 40 log lines ---'
    tail -n 40 build.log
    exit 1
  fi
  test -f t.pdf
"

reportResults
