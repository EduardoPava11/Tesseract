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
               quantization/PerfectQuantize.hs

# TesseractSpec.hs excluded from auto-run: needs Data.Array stub after KataGo removal.
# Run manually once imports are cleaned: make test-one F=quantization/TesseractSpec.hs

TEMPORAL = temporal/ContinuousDepthCadence.hs \
           temporal/DepthBinomial.hs \
           temporal/TemporalBinomial.hs \
           temporal/TemporalLoop.hs

SPATIAL = spatial/TesseractGo.hs

# ColorGraphs.hs and SpatialTransport.hs need System.Random — skip in CI.
SPATIAL_EXTRA = spatial/ColorGraphs.hs \
                spatial/SpatialTransport.hs

STATISTICS = statistics/BinomialCube.hs \
             statistics/BinomialFix.hs

# DeviationManifold.hs exceeds default read but compiles fine.
STATISTICS_EXTRA = statistics/DeviationManifold.hs

OUTPUT = output/FrameGeometry.hs \
         output/GenIcon.hs \
         output/BreakInvariants.hs

# RealTesseract, GIFAnalysis, TemporalSpatialGIF need source frames or ByteString.
OUTPUT_EXTRA = output/RealTesseract.hs \
               output/GIFAnalysis.hs \
               output/TemporalSpatialGIF.hs

CORE = $(ALGEBRA) $(QUANTIZATION) $(TEMPORAL) $(SPATIAL) $(STATISTICS) $(OUTPUT)

# ── Targets ──────────────────────────────────────────────

.PHONY: test test-algebra test-quantization test-temporal test-spatial test-statistics test-output test-one list

test:
	@echo "════ Tesseract Spec Suite ════"
	@pass=0; fail=0; \
	for f in $(CORE); do \
		printf "  %-45s" "$$f"; \
		if $(RUNGHC) $(FLAGS) $$f > /dev/null 2>&1; then \
			echo "✓"; pass=$$((pass+1)); \
		else \
			echo "✗"; fail=$$((fail+1)); \
		fi; \
	done; \
	echo ""; \
	echo "  $$pass passed, $$fail failed out of $$(( pass + fail ))"

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
