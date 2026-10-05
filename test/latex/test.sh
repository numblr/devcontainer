#!/usr/bin/env bash
set -e

source dev-container-features-test-lib

check "pdflatex installed" bash -c "pdflatex --version | head -n1"
check "bibtex installed" bash -c "bibtex --version | head -n1"
check "biber installed" bash -c "biber --version | head -n1"

# Compile a minimal document that uses the packages the set exists for, so a
# missing .sty fails here rather than mid-manuscript.
check "compiles a document using tikz/pgfplots/natbib/cleveref/mathtools/booktabs" bash -c '
  d=$(mktemp -d) && cd "$d" && cat > t.tex <<TEX
\documentclass{article}
\usepackage{tikz,pgfplots,natbib,cleveref,mathtools,bm,booktabs}
\begin{document}
\section{S}\label{sec:s}
\Cref{sec:s} $\bm{x}$
\begin{tabular}{@{}l@{}}\toprule a\\ \bottomrule\end{tabular}
\begin{tikzpicture}\draw (0,0)--(1,1);\end{tikzpicture}
\end{document}
TEX
  pdflatex -interaction=nonstopmode -halt-on-error t.tex >/dev/null && test -f t.pdf
'

reportResults
