# Kommander Charts

It might be a bit overly cautious, but following "better safe than sorry" approach, we're maintaining individual chart versions per supported Kommander addon version.

In case we need to release "Kommander 1.0.1" while already working on "Kommander 1.1", we need to be able to release a new chart version for "Kommander 1.0.1".

Tying chart version to appVersion and using revisions should help us being flexible while reducing overall version confusion.

We might find a better solution in future…
