/** The plates offered on the welcome screen. Each is a complete document that
 *  typesets on a cold cache, so "start from a plate" never lands on an error. */

export interface Plate {
  name: string;
  /** Shown under the name on the welcome screen. */
  note: string;
  source: string;
}

export const ARTICLE = `\\documentclass{article}
\\title{ScribeX}
\\author{}
\\date{}
\\begin{document}
\\maketitle

\\section{Offline by default}
This document was typeset locally by Tectonic, with no network access.

\\section{Mathematics}
\\begin{equation}
  \\int_{-\\infty}^{\\infty} e^{-x^2}\\,dx = \\sqrt{\\pi}
\\end{equation}

\\end{document}
`;

const LETTER = `\\documentclass{letter}
\\signature{}
\\address{}
\\begin{document}

\\begin{letter}{The Editor \\\\ The Journal}
\\opening{Dear Editor,}

Please find enclosed our manuscript for your consideration.

\\closing{Yours faithfully,}
\\end{letter}

\\end{document}
`;

const THESIS = `\\documentclass[12pt,oneside]{book}
\\title{A Thesis}
\\author{}
\\date{}
\\begin{document}
\\maketitle
\\tableofcontents

\\chapter{Introduction}
\\section{Background}
The problem, and why it matters.

\\section{Contribution}
What this thesis adds.

\\chapter{Method}
How it was done.

\\end{document}
`;

const BEAMER = `\\documentclass{beamer}
\\usetheme{default}
\\title{A Talk}
\\author{}
\\date{}
\\begin{document}

\\frame{\\titlepage}

\\begin{frame}{First slide}
  \\begin{itemize}
    \\item A point
    \\item Another point
  \\end{itemize}
\\end{frame}

\\end{document}
`;

export const PLATES: Plate[] = [
  { name: "Article", note: "A paper, with sections and maths", source: ARTICLE },
  { name: "Letter", note: "Correspondence, with an opening and a closing", source: LETTER },
  { name: "Thesis", note: "Chapters and a table of contents", source: THESIS },
  { name: "Beamer", note: "Slides", source: BEAMER },
];
