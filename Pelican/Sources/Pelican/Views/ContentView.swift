import QuickLook
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 360)
        } detail: {
            switch model.sidebarSelection {
            case .apps?:
                AppsView(inventory: model.inventory)
            case .cleanup?:
                CleanupView()
            default:
                AnalyzerView()
            }
        }
        .onChange(of: model.sidebarSelection) { selection in
            if case .location(let path)? = selection {
                model.open(path: path)
            }
        }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView()
                .environmentObject(model)
        }
        .alert(item: $model.alert) { item in
            item.makeAlert()
        }
        .quickLookPreview($model.quickLookURL)
    }
}

/// The main disk map: breadcrumb, visualisation and synchronised table.
struct AnalyzerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbBar()
            Divider()
            VSplitView {
                VisualizationPanel()
                    .frame(minHeight: 320, idealHeight: 520, maxHeight: .infinity)
                DetailTableView()
                    .frame(minHeight: 150, idealHeight: 280, maxHeight: .infinity)
            }
        }
        .navigationTitle(model.tree.map { $0[FileTree.root].name } ?? "Pelican")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Visualization", selection: $model.vizMode) {
                    ForEach(VizMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Switch between sunburst and treemap (⌘1 / ⌘2)")

                Picker("Size", selection: $model.metric) {
                    ForEach(SizeMetric.allCases) { metric in
                        Text(metric.label).tag(metric)
                    }
                }
                .help("Size on disk counts allocated blocks; logical size is the file length")

                Button {
                    model.rescan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .help("Rescan (⇧⌘R)")
                .disabled(model.tree == nil || model.phase == .scanning)

                Button {
                    model.chooseFolder()
                } label: {
                    Label("Scan Folder…", systemImage: "folder.badge.plus")
                }
                .help("Scan any folder or volume (⌘O)")
            }
        }
    }
}

struct BreadcrumbBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Button(action: model.zoomOut) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(model.tree == nil || model.focus == FileTree.root)
            .help("Enclosing folder (⌘↑)")

            if let tree = model.tree {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        let parentPath = (tree.rootPath as NSString).deletingLastPathComponent
                        if tree.rootPath != "/" && !parentPath.isEmpty {
                            Text(Format.displayPath(parentPath))
                                .foregroundStyle(.tertiary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        ForEach(Array(model.breadcrumb.enumerated()), id: \.element) { index, id in
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Button {
                                model.zoom(to: id)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(nsImage: IconCache.icon(for: tree[id], path: tree.path(of: id)))
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                    Text(tree[id].name)
                                        .fontWeight(id == model.focus ? .semibold : .regular)
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(id == model.focus ? Color.primary : Color.secondary)
                        }
                    }
                }
                Spacer(minLength: 8)
                Text("\(Format.bytes(tree[model.focus].size(model.metric))) · \(Format.count(tree[model.focus].itemCount)) items")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                Text(model.phase == .scanning ? "Scanning…" : "No location selected")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }
}
