import SwiftUI
import UniformTypeIdentifiers

struct LoadCustomButton: View {
    @ObservedObject private var mosesState: MosesState
    @State private var showFileImporter = false

    init(mosesState: MosesState) {
        self.mosesState = mosesState
    }

    var body: some View {
        VStack {
            Button(action: {
                showFileImporter = true
            }) {
                Text("Load Custom Model")
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType(filenameExtension: "gguf", conformingTo: .data)!],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let files):
                files.forEach { file in
                    let gotAccess = file.startAccessingSecurityScopedResource()
                    if !gotAccess { return }

                    do {
                        try mosesState.loadModel(modelUrl: file.absoluteURL)
                    } catch let err {
                        print("Error: \(err.localizedDescription)")
                    }

                    file.stopAccessingSecurityScopedResource()
                }
            case .failure(let error):
                print(error)
            }
        }
    }
}
