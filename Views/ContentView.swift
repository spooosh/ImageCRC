import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: ConversionViewModel

    @FocusState private var focusedField: SettingsPanelView.Field?

    private static let rightPanelWidth: CGFloat = 420

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            HStack(spacing: 0) {
                leftColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                rightPanel
                    .frame(width: Self.rightPanelWidth)
                    .frame(maxHeight: .infinity)
            }

            if viewModel.phase == .running {
                ProgressOverlayView(
                    progress: viewModel.progress,
                    completed: viewModel.completed,
                    total: viewModel.total,
                    currentFilename: viewModel.currentFilename,
                    onCancel: { viewModel.cancel() }
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focusedField = nil }
        .animation(.easeInOut(duration: 0.25), value: viewModel.phase)
        .animation(.easeInOut(duration: 0.25), value: viewModel.files.count)
        .sheet(isPresented: completionBinding) {
            if let summary = viewModel.summary {
                CompletionSheetView(summary: summary) {
                    viewModel.dismissCompletion()
                }
            }
        }
    }

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(spacing: 16) {
            header

            DropZoneView(
                hasFiles: !viewModel.files.isEmpty,
                onAdd: { viewModel.addURLs($0) },
                onBrowse: { viewModel.browseForFiles() }
            )

            if !viewModel.files.isEmpty {
                FileListView(
                    files: viewModel.files,
                    onRemove: { viewModel.remove($0) },
                    onClear: { viewModel.clearFiles() }
                )
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(24)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("ImageCRC")
                    .font(.title2.bold())
                Text("Bulk image optimizer & converter")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Right panel

    private var rightPanel: some View {
        VStack(spacing: 16) {
            SettingsPanelView(
                settings: $viewModel.settings,
                onChooseFolder: { viewModel.chooseOutputDirectory() },
                focus: $focusedField
            )

            Spacer(minLength: 0)

            actionBar
        }
        .padding(24)
    }

    private var actionBar: some View {
        Button {
            viewModel.start()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                Text(startButtonLabel)
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!viewModel.canStart)
        .pointingHandCursor()
    }

    private var startButtonLabel: String {
        switch viewModel.files.count {
        case 0: return "Convert"
        case 1: return "Convert 1 image"
        case let n: return "Convert \(n) images"
        }
    }

    private var completionBinding: Binding<Bool> {
        Binding(
            get: { viewModel.phase == .completed && viewModel.summary != nil },
            set: { newValue in
                if !newValue { viewModel.dismissCompletion() }
            }
        )
    }
}
