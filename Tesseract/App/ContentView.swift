// ContentView.swift
// Tesseract
//
// State machine UI: idle → previewing → recording → result
// Preview shows EXACTLY what the GIF will look like:
//   64×64 tesseract-quantized, displayed at 256×256 (4× scale)

import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraManager()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.state {
            case .idle:
                idleView

            case .previewing:
                previewView

            case .recording(let frame):
                recordingView(frame: frame)

            case .processing:
                processingView

            case .swiping(let gen):
                dualCubeView(generation: gen)

            case .done:
                if let gifData = camera.gifData, let measure = camera.gifMeasure {
                    GIFResultView(
                        gifData: gifData,
                        measure: measure,
                        onAgain: { camera.state = .previewing },
                        onShare: { shareGIF(gifData) }
                    )
                } else {
                    resultPlaceholder
                }

            case .error(let msg):
                errorView(msg)
            }
        }
        .onAppear { camera.start() }
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 16) {
            Text("TESSERACT")
                .font(.system(.title, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            Text("4⁴ = 256")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
            ProgressView()
                .tint(.white)
                .padding(.top, 8)
            Text("initializing camera...")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
        }
    }

    // MARK: - Live Preview (the main screen)

    private var previewView: some View {
        VStack(spacing: 0) {

            // Top: Birkhoff beauty gauge
            birkhoffGauge
                .padding(.top, 16)

            Spacer()

            // Center: 256×256 quantized preview (64×64 at 4× scale)
            quantizedPreview
                .padding(.horizontal, 24)

            // R, G, B, D channel previews
            channelPreviews
                .padding(.top, 12)

            Spacer()

            // Level picker: 64³ | 128²×32 | 256²×16
            levelPicker
                .padding(.bottom, 8)

            // Palette swatch (16×16 = 256 colors) + Record button
            HStack(alignment: .center, spacing: 24) {
                // 16×16 palette swatch on the left
                PaletteSwatchView()

                // Record button center
                recordButton

                // Balance spacing
                Color.clear.frame(width: 64, height: 64)
            }
            .padding(.bottom, 48)
        }
    }

    // MARK: - Quantized Preview (64×64 → 256×256)

    private var quantizedPreview: some View {
        ZStack {
            // Glass border
            RoundedRectangle(cornerRadius: 4)
                .fill(.ultraThinMaterial)
                .frame(
                    width: CGFloat(CameraConfig.displaySize + 8),
                    height: CGFloat(CameraConfig.displaySize + 8)
                )

            // The actual 64×64 image at 4× scale, nearest-neighbor
            if let cgImage = camera.previewImage {
                Image(decorative: cgImage, scale: 1.0)
                    .interpolation(.none)  // nearest neighbor — pixel-perfect
                    .resizable()
                    .frame(
                        width: CGFloat(CameraConfig.displaySize),
                        height: CGFloat(CameraConfig.displaySize)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(
                        width: CGFloat(CameraConfig.displaySize),
                        height: CGFloat(CameraConfig.displaySize)
                    )
                    .overlay(
                        Text("64 × 64")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.2))
                    )
            }

            // Grid overlay: 4×4 epoch grid (subtle)
            gridOverlay
        }
    }

    // MARK: - Grid Overlay (shows the 4⁴ structure)

    private var gridOverlay: some View {
        let size = CGFloat(CameraConfig.displaySize)
        let step = size / 4  // 4 divisions = tesseract axis levels

        return Canvas { context, canvasSize in
            let lineColor = Color.white.opacity(0.06)
            // Vertical lines
            for i in 1..<4 {
                let x = step * CGFloat(i) + 4  // offset for border
                var path = Path()
                path.move(to: CGPoint(x: x, y: 4))
                path.addLine(to: CGPoint(x: x, y: size + 4))
                context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
            }
            // Horizontal lines
            for i in 1..<4 {
                let y = step * CGFloat(i) + 4
                var path = Path()
                path.move(to: CGPoint(x: 4, y: y))
                path.addLine(to: CGPoint(x: size + 4, y: y))
                context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
            }
        }
        .frame(
            width: CGFloat(CameraConfig.displaySize + 8),
            height: CGFloat(CameraConfig.displaySize + 8)
        )
        .allowsHitTesting(false)
    }

    // MARK: - Birkhoff Beauty Gauge

    private var birkhoffGauge: some View {
        VStack(spacing: 4) {
            if let m = camera.previewMeasure {
                HStack(spacing: 12) {
                    Text("M")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))

                    // Beauty bar
                    GeometryReader { geo in
                        let width = geo.size.width
                        let normalized = min(1, m.beauty / 600)  // scale to [0,1]
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white.opacity(0.08))
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(.white.opacity(0.3 + Double(normalized) * 0.5))
                                    .frame(width: width * CGFloat(normalized))
                            }
                    }
                    .frame(height: 4)

                    Text(String(format: "%.0f", m.beauty))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.horizontal, 24)

                HStack(spacing: 16) {
                    metricLabel("O", String(format: "%.0f", m.order))
                    metricLabel("C", String(format: "%.2f", m.complexity))
                    metricLabel("dim", String(format: "%.1f", m.manifoldDim))
                    metricLabel("col", "\(m.colorsUsed)")
                }
            } else {
                Text("M = O / C")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
    }

    private func metricLabel(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))
        }
    }

    // MARK: - R, G, B, D Channel Previews

    private var channelPreviews: some View {
        HStack(spacing: 4) {
            channelThumb(image: camera.previewR, label: "R", tint: .red)
            channelThumb(image: camera.previewG, label: "G", tint: .green)
            channelThumb(image: camera.previewB, label: "B", tint: .blue)
            channelThumb(image: camera.previewD, label: "D", tint: .white)
        }
    }

    private func channelThumb(image: CGImage?, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            if let img = image {
                Image(decorative: img, scale: 1.0)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(tint.opacity(0.4), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.gray.opacity(0.1))
                    .frame(width: 48, height: 48)
            }
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(tint.opacity(0.6))
        }
    }

    // MARK: - Level Picker

    private var levelPicker: some View {
        VStack(spacing: 4) {
            // Segmented control for CubeMode
            Picker("Level", selection: Binding(
                get: { CameraConfig.mode },
                set: { CameraConfig.mode = $0 }
            )) {
                ForEach(CubeMode.allCases, id: \.self) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)

            // Info line: frames, duration, samples/block
            let level = CameraConfig.mode
            Text("\(level.frameCount) frames  \(String(format: "%.1f", Double(level.frameCount) / 20.0))s  \(CameraConfig.rgbStep * CameraConfig.rgbStep) px/blk")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Record Button

    private var recordButton: some View {
        Button(action: { camera.startRecording() }) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(.white.opacity(0.85))
                    .frame(width: 58, height: 58)
                // Tesseract icon: nested squares
                RoundedRectangle(cornerRadius: 3)
                    .stroke(.black.opacity(0.2), lineWidth: 1)
                    .frame(width: 20, height: 20)
                RoundedRectangle(cornerRadius: 2)
                    .stroke(.black.opacity(0.15), lineWidth: 1)
                    .frame(width: 12, height: 12)
                    .offset(x: 3, y: -3)
            }
        }
    }

    // MARK: - Recording View

    private func recordingView(frame: Int) -> some View {
        VStack(spacing: 16) {
            Spacer()

            if let cgImage = camera.previewImage {
                Image(decorative: cgImage, scale: 1.0)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 256, height: 256)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Text("\(frame) / 64")
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(.white)

            ProgressView(value: Double(frame) / 64.0)
                .tint(.white)
                .padding(.horizontal, 48)

            Text(String(format: "%.1fs", Double(frame) / 20.0))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))

            Spacer()
        }
    }

    // MARK: - Processing

    private var processingView: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("TESSERACT")
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))

            // Go board visualization (3 boards: R/G, G/B, B/R)
            if let boards = camera.processBoards {
                HStack(spacing: 8) {
                    goBoardView(board: boards.rg, label: "R/G", tintA: .red, tintB: .green)
                    goBoardView(board: boards.gb, label: "G/B", tintA: .green, tintB: .blue)
                    goBoardView(board: boards.br, label: "B/R", tintA: .blue, tintB: .red)
                }
                .padding(.horizontal, 16)
            } else {
                // Placeholder before first frame analyzed
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white.opacity(0.05))
                            .frame(width: 100, height: 100)
                    }
                }
            }

            // Progress bar
            VStack(spacing: 6) {
                ProgressView(value: Double(camera.processProgress))
                    .tint(.white)
                    .padding(.horizontal, 48)

                Text(String(format: "%.0f%%", camera.processProgress * 100))
                    .font(.system(.title2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))

                Text(camera.processPhase)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
    }

    // MARK: - Go Board Visualization

    private func goBoardView(board: GoBoard, label: String, tintA: Color, tintB: Color) -> some View {
        VStack(spacing: 2) {
            // 19×19 grid rendered as pixels
            Canvas { context, size in
                let cellSize = size.width / CGFloat(GoBoard.size)
                for y in 0..<GoBoard.size {
                    for x in 0..<GoBoard.size {
                        let stone = board[x, y]
                        let color: Color = switch stone {
                        case .black: tintA.opacity(0.8)
                        case .white: tintB.opacity(0.8)
                        case .empty: .gray.opacity(0.15)
                        }
                        let rect = CGRect(
                            x: CGFloat(x) * cellSize,
                            y: CGFloat(y) * cellSize,
                            width: cellSize, height: cellSize
                        )
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
            )

            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Share

    private func shareGIF(_ data: Data) {
        guard let url = GIFEncoder.saveToTempFile(data) else { return }

        // Share just the GIF file — no text overlay
        let controller = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        // iPad popover anchor
        controller.popoverPresentationController?.sourceView = UIView()

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        root.present(controller, animated: true)
    }

    // MARK: - Dual Cube View (two GIFs, synced at 20fps)

    @StateObject private var dualAnimator = DualCubeAnimator(
        cubeA: VoxelCube(), cubeB: VoxelCube()
    )

    /// Blend slider position: 0 = pure A, 1 = pure B
    @State private var blendAlpha: Float = 0.5

    private func dualCubeView(generation: Int) -> some View {
        VStack(spacing: 0) {

            // ── GIF A (top point in gene space) ──
            gifPointView(frame: dualAnimator.frameA, label: "A", gene: "current")
                .onTapGesture { camera.tapAccept() }  // tap A = accept gene A

            Spacer(minLength: 8)

            // ── Blend zone: drag to combine A + B ──
            blendSlider

            Spacer(minLength: 8)

            // ── GIF B (bottom point in gene space) ──
            gifPointView(frame: dualAnimator.frameB, label: "B", gene: "explored")
                .onTapGesture {
                    // tap B = swap: make B the current, generate new B
                    camera.currentGene = dualAnimator.geneB
                    dualAnimator.geneA = dualAnimator.geneB
                    dualAnimator.geneB = dualAnimator.geneB.perturbed(
                        scale: 0.05, seed: UInt32(generation + 1)
                    )
                    camera.swipeGeneration += 1
                    camera.state = .swiping(camera.swipeGeneration)
                }

            // Frame sync indicator
            Text("\(dualAnimator.frameIndex + 1)/\(dualAnimator.totalFrames)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
                .padding(.bottom, 8)
        }
        .onAppear {
            let cube = camera.buildVoxelCube()
            let geneA = camera.currentGene
            let geneB = camera.currentGene.perturbed(scale: 0.05, seed: 42)
            dualAnimator.cubeA = cube
            dualAnimator.cubeB = cube
            dualAnimator.geneA = geneA
            dualAnimator.geneB = geneB
            dualAnimator.newFramesA = cube.sliceAll(axis: .z)
            dualAnimator.newFramesB = cube.sliceAll(axis: .z)
            dualAnimator.oldFramesA = dualAnimator.newFramesA
            dualAnimator.oldFramesB = dualAnimator.newFramesB
            dualAnimator.totalFrames = VoxelCube.size
            dualAnimator.startPlayback()
        }
        .onDisappear {
            dualAnimator.stopPlayback()
        }
    }

    // ── One GIF point (portrait, centered) ──

    private func gifPointView(frame: [UInt8], label: String, gene: String) -> some View {
        VStack(spacing: 4) {
            if !frame.isEmpty, let image = camera.buildPreviewImage(indices: frame) {
                Image(decorative: image, scale: 1.0)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 200, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.05))
                    .frame(width: 200, height: 200)
            }
            Text("\(label) · \(gene)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    // ── Blend slider: combine A and B ──

    private var blendSlider: some View {
        VStack(spacing: 4) {
            // The composite GIF (interpolated between A and B)
            let compositeFrame = blendFrames(
                frameA: dualAnimator.frameA,
                frameB: dualAnimator.frameB,
                alpha: blendAlpha
            )
            if !compositeFrame.isEmpty, let image = camera.buildPreviewImage(indices: compositeFrame) {
                Image(decorative: image, scale: 1.0)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
            }

            // Slider: α from 0 (pure A) to 1 (pure B)
            HStack(spacing: 8) {
                Text("A")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                Slider(value: Binding(
                    get: { Double(blendAlpha) },
                    set: { blendAlpha = Float($0) }
                ), in: 0...1)
                .tint(.white.opacity(0.4))
                .frame(maxWidth: 160)
                Text("B")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }

            // Accept composite
            Button("combine") {
                // Create the interpolated gene and accept it
                let composite = interpolateGenes(
                    alpha: blendAlpha,
                    geneA: dualAnimator.geneA,
                    geneB: dualAnimator.geneB
                )
                camera.currentGene = composite
                camera.tapAccept()
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    /// Blend two palette index frames: per-pixel, gene-interpolated
    /// α=0 → pure A, α=1 → pure B
    private func blendFrames(frameA: [UInt8], frameB: [UInt8], alpha: Float) -> [UInt8] {
        guard frameA.count == frameB.count, !frameA.isEmpty else { return frameA }
        // Interpolate the gene weights, then re-run forward pass
        // For display speed: simple per-pixel blend of palette indices
        // (true interpolation happens when "combine" is tapped)
        if alpha < 0.5 { return frameA }
        else { return frameB }
        // TODO: real interpolation via gene lerp + forward pass
    }

    // MARK: - OLD Swiping View (kept for reference)

    @State private var swipeOffset: CGFloat = 0

    private func swipingView(gifData: Data, generation: Int) -> some View {
        VStack(spacing: 12) {
            // Generation + coverage
            HStack {
                Text("gen \(generation)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("\(camera.eliteMap.coverage)/9 explored")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 24)

            // Current GIF (swipeable)
            GIFPlayerView(data: gifData)
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .offset(x: swipeOffset)

            // Beauty measure
            if let measure = camera.gifMeasure {
                Text("M=\(String(format: "%.1f", measure.beauty))  colors=\(measure.colorsUsed)/256")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }

            // Swipe hints
            HStack(spacing: 24) {
                Label("explore", systemImage: "arrow.left")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                Label("accept", systemImage: "hand.tap")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                Label("revert", systemImage: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }

            // ── 3×3 MAP-Elites Grid ──
            mapElitesGrid
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .gesture(
            DragGesture(minimumDistance: 40)
                .onChanged { value in
                    swipeOffset = value.translation.width * 0.5
                }
                .onEnded { value in
                    withAnimation(.spring(duration: 0.2)) { swipeOffset = 0 }
                    if value.translation.width < -60 {
                        camera.swipeLeft()   // LEFT = explore (Sobol)
                    } else if value.translation.width > 60 {
                        camera.swipeRight()  // RIGHT = revert
                    }
                }
        )
    }

    // MARK: - MAP-Elites 3×3 Grid

    private var mapElitesGrid: some View {
        VStack(spacing: 2) {
            // Column labels
            HStack(spacing: 2) {
                Text("")
                    .frame(width: 40)
                ForEach(0..<3, id: \.self) { col in
                    Text(EliteMap.colLabels[col])
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(maxWidth: .infinity)
                }
            }

            // Grid rows (top = high rhythm, bottom = low)
            ForEach((0..<3).reversed(), id: \.self) { row in
                HStack(spacing: 2) {
                    // Row label
                    Text(EliteMap.rowLabels[row])
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(width: 40, alignment: .trailing)

                    // 3 cells
                    ForEach(0..<3, id: \.self) { col in
                        mapCell(row: row, col: col)
                    }
                }
            }
        }
    }

    private func mapCell(row: Int, col: Int) -> some View {
        let cell = camera.eliteMap.cells[row][col]
        return Button(action: {
            // TAP a cell → accept that gene
            if let elite = cell {
                camera.currentGene = elite.gene
                camera.gifData = elite.gifData
                camera.gifMeasure = BirkhoffMeasure(
                    counts: [Int](repeating: 16, count: 256)  // placeholder
                )
                camera.tapAccept()
            }
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(cell != nil
                        ? Color.white.opacity(0.15)
                        : Color.white.opacity(0.03))
                    .frame(height: 56)

                if let elite = cell {
                    VStack(spacing: 2) {
                        // Tiny GIF thumbnail
                        GIFPlayerView(data: elite.gifData)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 2))

                        // Beauty score
                        Text(String(format: "%.0f", elite.beauty))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                } else {
                    // Empty cell
                    Text("·")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.1))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Result Placeholder

    private var resultPlaceholder: some View {
        VStack(spacing: 16) {
            Text("GIF ready")
                .font(.system(.headline, design: .monospaced))
            Button("Again") { camera.state = .previewing }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Error

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Text("error")
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(.red.opacity(0.7))
            Text(msg)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry") { camera.state = .idle; camera.start() }
                .buttonStyle(.bordered)
        }
    }
}

// MARK: - GIF Result View

struct GIFResultView: View {
    let gifData: Data
    let measure: BirkhoffMeasure
    let onAgain: () -> Void
    let onShare: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // The GIF — full focus, 256×256 nearest-neighbor
            GIFPlayerView(data: gifData)
                .frame(width: 256, height: 256)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .white.opacity(0.05), radius: 20)

            Spacer()

            // Share button — the only action that matters
            Button(action: onShare) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share")
                }
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.bottom, 16)

            // Retake — subtle
            Button(action: onAgain) {
                Text("Retake")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.bottom, 48)
        }
    }
}

#Preview {
    ContentView()
}
