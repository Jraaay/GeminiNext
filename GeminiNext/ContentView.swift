//
//  ContentView.swift
//  GeminiNext
//
//  Created by Jray on 2026/2/10.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: WebViewModel

    var body: some View {
        ZStack {
            GeminiWebView(viewModel: viewModel)
                .frame(minWidth: 800, minHeight: 600)

            // Loading indicator (shown only when there is no error)
            if viewModel.isLoading && viewModel.errorMessage == nil {
                ProgressView("Loading Gemini...")
                    .progressViewStyle(.circular)
                    .padding(20)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
                    .cornerRadius(10)
            }

            // Error message and retry
            if let errorMessage = viewModel.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(errorMessage)
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Button("Reload") {
                        viewModel.retry()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(30)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
                .cornerRadius(12)
            }
        }
    }
}

#Preview {
    ContentView(viewModel: WebViewModel())
}
