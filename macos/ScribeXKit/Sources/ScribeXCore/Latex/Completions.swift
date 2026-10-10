import Foundation

// The words the source editor offers as you type: commands after a backslash,
// environment names inside \begin{…}.

public let latexCommands = [
    "documentclass", "usepackage", "begin", "end", "section", "subsection",
    "subsubsection", "paragraph", "textbf", "textit", "texttt", "emph",
    "label", "ref", "eqref", "cite", "footnote", "item", "caption",
    "includegraphics", "frac", "sqrt", "sum", "int", "left", "right",
    "alpha", "beta", "gamma", "delta", "theta", "lambda", "mu", "pi", "sigma",
    "infty", "partial", "nabla", "cdot", "times", "leq", "geq", "neq", "approx",
]

public let latexEnvironments = [
    "document", "equation", "equation*", "align", "align*", "gather",
    "itemize", "enumerate", "description", "figure", "table", "tabular",
    "center", "quote", "verbatim", "abstract", "theorem", "proof", "matrix",
]
