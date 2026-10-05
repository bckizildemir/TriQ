//
//  AIPreviewHelpers.swift
//  TTB
//
//  Created by AI Assistant on 2025-07-18.
//

import SwiftUI

// MARK: - AI Preview Helpers

struct AIPreviewContainer<Content: View>: View {
    let content: Content
    let title: String
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        NavigationView {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct AIPreviewStates: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Group {
                    Text(String(localized: "ai.preview.states.loading"))
                        .font(.headline)
                        .padding()
                    
                    AILoadingView(message: String(localized: "ai.preview.loadingThinking"))
                        .frame(height: 200)
                    
                    AILoadingView(message: String(localized: "ai.preview.loadingResponses"))
                        .frame(height: 200)
                    
                    Text(String(localized: "ai.preview.states.error"))
                        .font(.headline)
                        .padding()
                    
                    AIErrorView(error: String(localized: "ai.preview.error.network")) {
                        print("Retry tapped")
                    }
                    .frame(height: 300)
                    
                    AINetworkErrorView {
                        print("Network retry tapped")
                    }
                    .frame(height: 300)
                    
                    AIRateLimitErrorView {
                        print("Rate limit retry tapped")
                    }
                    .frame(height: 300)
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle(String(localized: "ai.preview.title.states"))
    }
}

struct AIQueryCardPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(AIQuery.sampleQueries) { query in
                    AIQueryCard(query: query)
                        .environmentObject(AIModel.sample)
                }
            }
            .padding()
        }
        .navigationTitle(String(localized: "ai.preview.queryCards"))
    }
}

struct AIAccessibilityPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(String(localized: "ai.preview.accessibility.title"))
                    .font(.title)
                    .padding()
                
                // Test Dynamic Type
                Group {
                    Text(String(localized: "ai.preview.dynamicType"))
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "ai.preview.smallFont"))
                            .font(.caption)
                        Text(String(localized: "ai.preview.regularFont"))
                            .font(.body)
                        Text(String(localized: "ai.preview.largeFont"))
                            .font(.title3)
                        Text(String(localized: "ai.preview.extraLargeFont"))
                            .font(.title)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.theme.secondaryBackground)
                    .cornerRadius(12)
                }
                
                // Test Color Contrast
                Group {
                    Text(String(localized: "ai.preview.colorContrast"))
                        .font(.headline)
                    
                    VStack(spacing: 8) {
                        HStack {
                            Text(String(localized: "ai.preview.primaryOnBackground"))
                                .foregroundColor(.primary)
                            Spacer()
                            Text(String(localized: "ai.preview.secondaryOnBackground"))
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.theme.background)
                        .cornerRadius(8)
                        
                        HStack {
                            Text(String(localized: "ai.preview.whiteOnAccent"))
                                .foregroundColor(.white)
                            Spacer()
                            Text(String(localized: "ai.preview.accentOnBackground"))
                                .foregroundColor(.accentColor)
                        }
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(8)
                    }
                    .padding()
                    .background(Color.theme.secondaryBackground)
                    .cornerRadius(12)
                }
                
                // Test Button Accessibility
                Group {
                    Text(String(localized: "ai.preview.buttonAccessibility"))
                        .font(.headline)
                    
                    VStack(spacing: 12) {
                        Button(String(localized: "ai.preview.primaryAction")) {
                            print("Primary tapped")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel(String(localized: "ai.preview.primaryActionLabel"))
                        .accessibilityHint(String(localized: "ai.preview.primaryActionHint"))
                        
                        Button(String(localized: "ai.preview.secondaryAction")) {
                            print("Secondary tapped")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(String(localized: "ai.preview.secondaryActionLabel"))
                        .accessibilityHint(String(localized: "ai.preview.secondaryActionHint"))
                        
                        Button(String(localized: "ai.preview.destructiveAction")) {
                            print("Destructive tapped")
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                        .accessibilityLabel(String(localized: "ai.preview.destructiveActionLabel"))
                        .accessibilityHint(String(localized: "ai.preview.destructiveActionHint"))
                    }
                    .padding()
                    .background(Color.theme.secondaryBackground)
                    .cornerRadius(12)
                }
            }
            .padding()
        }
        .navigationTitle(String(localized: "ai.preview.accessibility"))
    }
}

// MARK: - Preview Providers

struct AIPreviewHelpers_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AIPreviewContainer(title: String(localized: "ai.preview.title.states")) {
                AIPreviewStates()
            }
            .previewDisplayName(String(localized: "ai.preview.title.states"))
            
            AIPreviewContainer(title: String(localized: "ai.preview.queryCards")) {
                AIQueryCardPreview()
            }
            .previewDisplayName(String(localized: "ai.preview.queryCards"))
            
            AIPreviewContainer(title: String(localized: "ai.preview.accessibility")) {
                AIAccessibilityPreview()
            }
            .previewDisplayName(String(localized: "ai.preview.accessibility"))
            
            // Test with different accessibility settings
            AIPreviewContainer(title: String(localized: "ai.preview.largeText")) {
                AIAccessibilityPreview()
            }
            .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
            .previewDisplayName(String(localized: "ai.preview.largeText"))
            
            AIPreviewContainer(title: String(localized: "ai.preview.darkMode")) {
                AIAccessibilityPreview()
            }
            .preferredColorScheme(.dark)
            .previewDisplayName(String(localized: "ai.preview.darkMode"))
        }
    }
}
