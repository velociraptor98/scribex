/// Templates offered on the welcome screen. The first-run download fetches
/// everything they use, so each builds offline.
public struct Plate: Hashable, Sendable, Identifiable {
    public var name: String
    /// Shown under the name on the welcome screen.
    public var note: String
    public var source: String

    public var id: String { name }
}

public let articleSource = #"""
\documentclass{article}
\title{ScribeX}
\author{}
\date{}
\begin{document}
\maketitle

\section{Introduction}
Start writing here.

\section{Mathematics}
\begin{equation}
  \int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
\end{equation}

\end{document}

"""#

private let letterSource = #"""
\documentclass{letter}
\signature{}
\address{}
\begin{document}

\begin{letter}{The Editor \\ The Journal}
\opening{Dear Editor,}

Please find enclosed our manuscript for your consideration.

\closing{Yours faithfully,}
\end{letter}

\end{document}

"""#

private let thesisSource = #"""
\documentclass[12pt,oneside]{book}
\title{A Thesis}
\author{}
\date{}
\begin{document}
\maketitle
\tableofcontents

\chapter{Introduction}
\section{Background}
The problem, and why it matters.

\section{Contribution}
What this thesis adds.

\chapter{Method}
How it was done.

\end{document}

"""#

private let beamerSource = #"""
\documentclass{beamer}
\usetheme{default}
\title{A Talk}
\author{}
\date{}
\begin{document}

\frame{\titlepage}

\begin{frame}{First slide}
  \begin{itemize}
    \item A point
    \item Another point
  \end{itemize}
\end{frame}

\end{document}

"""#

public let plates: [Plate] = [
    Plate(name: "Article", note: "A paper, with sections and maths", source: articleSource),
    Plate(name: "Letter", note: "Correspondence, with an opening and a closing", source: letterSource),
    Plate(name: "Thesis", note: "Chapters and a table of contents", source: thesisSource),
    Plate(name: "Beamer", note: "Slides", source: beamerSource),
]
