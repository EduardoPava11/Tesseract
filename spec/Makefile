# Tesseract Haskell Specs
# Run: make test          (all specs)
#      make test-algebra   (just algebra layer)
#      make test-one F=algebra/Tesseract.hs

RUNGHC = runghc
# -package-env=- ignores GHCup default env that hides array/containers
FLAGS  = -W -package-env=-

# ── File lists by layer ──────────────────────────────────

ALGEBRA = algebra/Tesseract.hs \
          algebra/DirectSum.hs \
          algebra/TesseractDistances.hs

QUANTIZATION = quantization/TesseractAxes.hs \
               quantization/TesseractQuantize.hs \
               quantization/PerfectQuantize.hs \
               quantization/BellPalette.hs \
               quantization/ResolutionLadder.hs \
               quantization/DitherRamp.hs \
               quantization/Centers.hs \
               quantization/CentroidRefine.hs \
               quantization/DyadPalette.hs \
               quantization/PairPermutations.hs \
               quantization/SpectralPalette.hs \
               quantization/PhasePalette.hs \
               quantization/PairTree.hs \
               quantization/RoleAllocation.hs \
               quantization/Octave.hs \
               quantization/AttractorRAG.hs \
               quantization/GroundHue.hs \
               quantization/WhiteBalance.hs

# TesseractSpec.hs excluded from auto-run: needs Data.Array stub after KataGo removal.
# Run manually once imports are cleaned: make test-one F=quantization/TesseractSpec.hs

TEMPORAL = temporal/ContinuousDepthCadence.hs \
           temporal/DepthSignal.hs \
           temporal/DepthMixture.hs \
           temporal/FaceCadence.hs \
           temporal/DepthBinomial.hs \
           temporal/TemporalBinomial.hs \
           temporal/TemporalLoop.hs \
           temporal/MixtureStability.hs

SPATIAL = spatial/TesseractGo.hs

# ColorGraphs.hs and SpatialTransport.hs need System.Random — skip in CI.
SPATIAL_EXTRA = spatial/ColorGraphs.hs \
                spatial/SpatialTransport.hs

STATISTICS = statistics/BinomialCube.hs \
             statistics/BinomialFix.hs \
             statistics/WassersteinPalette.hs \
             statistics/StatsVariance.hs \
             statistics/PhaseEnergy.hs \
             statistics/TilingEntropy.hs \
             statistics/Dissonance.hs \
             statistics/PhaseTiling.hs

# DeviationManifold.hs exceeds default read but compiles fine.
STATISTICS_EXTRA = statistics/DeviationManifold.hs

NEURAL = neural/BayerResidual.hs \
         neural/ANELoop.hs \
         neural/SKGeneCalculus.hs \
         neural/SKGeneSemantics.hs \
         neural/OctaveCodec.hs \
         neural/DescentLadder.hs \
         neural/JepaH.hs \
         neural/WeaveState.hs

UI = ui/CellMechanics.hs \
     ui/SurfaceMachine.hs \
     ui/EditMachine.hs \
     ui/WidgetGrid.hs \
     ui/DetentDial.hs

HARMONY = harmony/SetListDissonance.hs

# GenIcon.hs takes ~2m and renders the app icon — run via `make icon`.
OUTPUT = output/FrameGeometry.hs \
         output/BreakInvariants.hs \
         output/ExportMethods.hs \
         output/TriScaleLadder.hs \
         output/RateLadder.hs \
         output/FeedCompression.hs

# RealTesseract, GIFAnalysis, TemporalSpatialGIF need source frames or ByteString.
OUTPUT_EXTRA = output/RealTesseract.hs \
               output/GIFAnalysis.hs \
               output/TemporalSpatialGIF.hs

CORE = $(ALGEBRA) $(QUANTIZATION) $(TEMPORAL) $(SPATIAL) $(STATISTICS) $(NEURAL) $(UI) $(HARMONY) $(OUTPUT)

# ── Targets ──────────────────────────────────────────────

.PHONY: test test-algebra test-quantization test-temporal test-spatial test-statistics test-output test-one list

# TRUTHFUL harness: a file fails on nonzero exit OR any "✗" it prints.
# (Most spec mains predate exitFailure; grepping their own failure marks
# closes the exit-code blindness. "⊘" marks superseded checks — allowed.)
test:
	@echo "════ Tesseract Spec Suite ════"
	@pass=0; fail=0; \
	for f in $(CORE); do \
		printf "  %-45s" "$$f"; \
		out=$$($(RUNGHC) $(FLAGS) $$f 2>&1); rc=$$?; \
		if [ $$rc -eq 0 ] && ! printf '%s' "$$out" | grep -q "✗"; then \
			echo "✓"; pass=$$((pass+1)); \
		else \
			echo "✗"; fail=$$((fail+1)); \
			printf '%s\n' "$$out" | grep "✗" | head -4 | sed 's/^/      /'; \
		fi; \
	done; \
	echo ""; \
	echo "  $$pass passed, $$fail failed out of $$(( pass + fail ))"; \
	[ $$fail -eq 0 ]

icon:
	@echo "════ GenIcon (slow, ~2m) ════"
	@$(RUNGHC) $(FLAGS) output/GenIcon.hs

# Emit the gene-JEPA training corpus → nn/sk-gene/corpus/
corpus:
	@$(RUNGHC) $(FLAGS) output/SKCorpusEmit.hs

# Emit the descent-ladder training corpus → nn/descent/corpus/
corpus-descent:
	@$(RUNGHC) $(FLAGS) output/DescentCorpusEmit.hs

# Emit the JEPA-H trajectory corpus → nn/jepa/corpus/
corpus-jepa:
	@$(RUNGHC) $(FLAGS) output/JepaCorpusEmit.hs

test-verbose:
	@for f in $(CORE); do \
		echo ""; \
		echo "════ $$f ════"; \
		$(RUNGHC) $(FLAGS) $$f || true; \
	done

test-algebra:
	@for f in $(ALGEBRA); do echo "════ $$f ════"; $(RUNGHC) $(FLAGS) $$f; echo ""; done

test-quantization:
	@for f in $(QUANTIZATION); do echo "════ $$f ════"; $(RUNGHC) $(FLAGS) $$f; echo ""; done

test-temporal:
	@for f in $(TEMPORAL); do echo "════ $$f ════"; $(RUNGHC) $(FLAGS) $$f; echo ""; done

test-spatial:
	@for f in $(SPATIAL); do echo "════ $$f ════"; $(RUNGHC) $(FLAGS) $$f; echo ""; done

test-statistics:
	@for f in $(STATISTICS); do echo "════ $$f ════"; $(RUNGHC) $(FLAGS) $$f; echo ""; done

test-output:
	@for f in $(OUTPUT); do echo "════ $$f ════"; $(RUNGHC) $(FLAGS) $$f; echo ""; done

# Run a single spec: make test-one F=algebra/Tesseract.hs
test-one:
	$(RUNGHC) $(FLAGS) $(F)

list:
	@echo "Core specs (runnable without extra deps):"
	@for f in $(CORE); do echo "  $$f"; done
	@echo ""
	@echo "Extra specs (need System.Random, ByteString, or source frames):"
	@for f in $(SPATIAL_EXTRA) $(STATISTICS_EXTRA) $(OUTPUT_EXTRA); do echo "  $$f"; done
