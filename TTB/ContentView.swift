//
//  ContentView.swift
//  TTB
//
//  Created by Berke Can KIZILDEMİR on 31/01/2025.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text(String(localized: "content.placeholder.hello"))
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
