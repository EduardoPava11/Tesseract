# docs/adversarial

What this directory is: the register of claims the Tesseract repo makes
about itself, and whether anything actually checks them. It exists
because "the suite is green" was being reported as if it were evidence,
when the suite was written by the same hand that wrote the code, aimed
at the same target.

The repo had already proved this twice on its own. Quantize.metal
claimed to be "verified by Haskell axioms G5-G10 for all 4096 output
pixels" while applying a 90 degree rotation the spec did not, because
G5 (bounds), G6 (alignment) and G7 (spacing) are every one of them
invariant under a relabelling of the output grid. They could not have
caught it. And MerkleSearch restated TilingEntropy's measurements in its
own comment table, got them wrong, and stayed green because its axioms
quantified over that table rather than over TilingEntropy. Those two are
the templates. Everything in FINDINGS.md is one of them or the third
case, a law with two implementations and no test between them.

How the run was structured. Four adversaries worked in parallel, one per
dimension: VACUOUS (axioms that cannot fail), PORTS (Haskell versus
Swift versus Metal), NUMBERS (published figures versus the code that
produces them), CHAIN (documented reasoning versus what the code does).
Each was read only on app and spec source and was required to produce a
concrete break test, a command or a mutation someone else can run, not
an argument. Every finding was then handed to an independent skeptic
whose sole job was to refute it: reproduce the break test, hunt for a
gate the finder missed, and check whether the consequence is real.
Three of eight findings died there, and the kill reasons are kept in
FINDINGS.md because a killed finding is positive evidence that the axiom
base is sound at that point. Two survivors had their diagnosis corrected
by the skeptic and four had their severity lowered. Severities in
FINDINGS.md are the skeptic's, not the finder's.

THE STANDING RULE. A claim without a sufficient gate is UNGATED, not
green. Correct by inspection is UNGATED. A gate that pins the parameters
handed to an engine, rather than the picture that comes out of it, is
UNGATED. A gate that quantifies over its own restated literals is
VACUOUS, which is worse than UNGATED because it reports success. Nine
claims in CLAIM-REGISTER.md are UNGATED today and four are VACUOUS,
against 28 PROVEN. Those 28 are in the register on purpose: a register
that lists only failures is not a register, and the sound half is what
tells you which patterns to copy.

FILES
* FINDINGS.md, the five survivors ranked most severe first, each with
  target, claim, defect, runnable break test and skeptic verdict, then
  the three killed findings and why.
* CLAIM-REGISTER.md, 51 claims examined, one row each, with what gates
  them and a status of PROVEN, VACUOUS, UNGATED, DIVERGENT or UNKNOWN.

Note on quotations: the repo's own text uses dashes in several of the
lines quoted here. Per the standing house style those were replaced with
commas, colons or parentheses. Nothing else in a quotation was altered.
