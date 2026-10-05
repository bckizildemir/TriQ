//
//  AIErrorView.swift
//  TTB
//
//  Created by AI Assistant on 2025-07-18.
//

import SwiftUI

struct AIErrorView: View {
    let error: String
    let retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Error Icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            // Error Title
            Text(String(localized: "ai.errorView.title"))
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            // Error Message
            Text(error)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 20)
            
            // Retry Button
            Button(action: retryAction) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .font(.body)
                    
                    Text(String(localized: "ai.errorView.rateLimit.action"))
                        .font(.body)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            
            // Additional Help
            VStack(spacing: 8) {
                Text(String(localized: "ai.errorView.helpTitle"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(spacing: 4) {
                    Text(String(localized: "ai.errorView.help.internet"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(String(localized: "ai.errorView.help.limit"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(String(localized: "ai.errorView.help.wait"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Specialized Error Views
struct AINetworkErrorView: View {
    let retryAction: () -> Void
    
    var body: some View {
        AIErrorView(
            error: String(localized: "ai.errorView.network.message"),
            retryAction: retryAction
        )
    }
}

struct AIRateLimitErrorView: View {
    let retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.fill")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text(String(localized: "ai.errorView.rateLimit.title"))
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text(String(localized: "ai.errorView.rateLimit.message"))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 20)
            
            Button(action: retryAction) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .font(.body)
                    
                    Text(String(localized: "common.retry"))
                        .font(.body)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct AIAPIKeyErrorView: View {
    let retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            Text(String(localized: "ai.errorView.apiKey.title"))
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text(String(localized: "ai.errorView.apiKey.message"))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 20)
            
            Button(action: retryAction) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .font(.body)
                    
                    Text(String(localized: "common.retry"))
                        .font(.body)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Preview
struct AIErrorView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Generic Error - Light Mode
            AIErrorView(error: "Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.") {
                print("Retry tapped")
            }
            .previewDisplayName("Generic Error - Light")
            
            // Generic Error - Dark Mode
            AIErrorView(error: "Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.") {
                print("Retry tapped")
            }
            .preferredColorScheme(.dark)
            .previewDisplayName("Generic Error - Dark")
            
            // Network Error
            AINetworkErrorView {
                print("Network retry tapped")
            }
            .previewDisplayName("Network Error")
            
            // Rate Limit Error
            AIRateLimitErrorView {
                print("Rate limit retry tapped")
            }
            .previewDisplayName("Rate Limit Error")
            
            // API Key Error
            AIAPIKeyErrorView {
                print("API key retry tapped")
            }
            .previewDisplayName("API Key Error")
            
            // Long Error Message
            AIErrorView(error: "Bu çok uzun bir hata mesajıdır. Birden fazla satıra yayılacak ve kullanıcıya detaylı bilgi verecektir. Ağ bağlantınızı kontrol edin, uygulamayı yeniden başlatın ve tekrar deneyin.") {
                print("Long error retry tapped")
            }
            .previewDisplayName("Long Error Message")
            
            // Short Error Message
            AIErrorView(error: "Hata!") {
                print("Short error retry tapped")
            }
            .previewDisplayName("Short Error Message")
            
            // Error in Navigation View
            NavigationView {
                AIErrorView(error: "Navigasyon içindeki hata mesajı") {
                    print("Navigation error retry tapped")
                }
                .navigationTitle("Hata Sayfası")
                .navigationBarTitleDisplayMode(.inline)
            }
            .previewDisplayName("In Navigation View")
        }
    }
}
