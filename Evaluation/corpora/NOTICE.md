# Corpus provenance

`public-domain.json` contains the 28 public-domain, source-only passages locked
for Margin's v0.1.0 blind evaluation. It contains no Apple, DeepSeek, or other
provider output. The passages are four selections from each of seven works:

| Project Gutenberg eBook | Work | Author |
| --- | --- | --- |
| [23](https://www.gutenberg.org/ebooks/23) | *Narrative of the Life of Frederick Douglass, an American Slave* | Frederick Douglass |
| [148](https://www.gutenberg.org/ebooks/148) | *The Autobiography of Benjamin Franklin* | Benjamin Franklin |
| [1342](https://www.gutenberg.org/ebooks/1342) | *Pride and Prejudice* | Jane Austen |
| [11](https://www.gutenberg.org/ebooks/11) | *Alice's Adventures in Wonderland* | Lewis Carroll |
| [1404](https://www.gutenberg.org/ebooks/1404) | *The Federalist Papers* | Alexander Hamilton, John Jay, and James Madison |
| [22764](https://www.gutenberg.org/ebooks/22764) | *On the Origin of Species by Means of Natural Selection* | Charles Darwin |
| [98](https://www.gutenberg.org/ebooks/98) | *A Tale of Two Cities* | Charles Dickens |

Project Gutenberg marks each listed eBook as public domain in the United
States. Each corpus item links to the corresponding UTF-8 plain-text source and
retains its eBook number in the license field. Gutenberg line wrapping,
plain-text emphasis markers, and printed-page markers were normalized for
reading; the wording and punctuation were not modernized. The MIT license for
Margin's source code does not claim copyright over these excerpts and does not
replace Project Gutenberg's license or trademark terms.

Public-domain status can vary by jurisdiction. Anyone redistributing this
corpus must confirm that each source is usable where they publish it and follow
the applicable [Project Gutenberg License](https://www.gutenberg.org/policy/license.html).

`development-public-domain.json` is a separate qualification set and is never
part of the held-out score. It contains two selections apiece from Project
Gutenberg eBooks [1260](https://www.gutenberg.org/ebooks/1260),
[2701](https://www.gutenberg.org/ebooks/2701),
[84](https://www.gutenberg.org/ebooks/84),
[35](https://www.gutenberg.org/ebooks/35), and
[345](https://www.gutenberg.org/ebooks/345). Project Gutenberg marks all five
as public domain in the United States. Their works and passage texts are kept
separate from the formal public-domain corpus.

Modern books, news articles, and private reading selections do not belong here.
Store them only in `Evaluation/private/` using a `.local.json` or
`.private.json` filename. Private sources and candidate translations must never
be copied into this tracked corpus.
