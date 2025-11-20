//
//  Main.swift
//  test
//
//  Created by Binaria on 04.11.2025..
//

import SwiftUI

@main
struct testApp: App {
    var body: some Scene {
        WindowGroup {
            GStreamerContainer()
                .edgesIgnoringSafeArea(.all) // make it fill the screen
        }
    }
}
