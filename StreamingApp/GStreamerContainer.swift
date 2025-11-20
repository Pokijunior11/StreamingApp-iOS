//
//  GStreamerContainer.swift
//  agora
//
//  Created by Binaria on 05.11.2025..
//


import SwiftUI

struct GStreamerContainer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        gst_ios_init()

        /*
        agoraBridge = AgoraBridge()
        agoraBridge.initAgora(withAppId: "b937f258b1464ffd8bfc81cadc482c41",
                              token: "007eJxTYJiXoj1TzXsDd54OY73LwfkdNk7aJ+e08MdfZk+e2G3qeFeBIcnS2DzNyNQiydDEzCQtLcUiKS3ZwjA5MSXZxMIo2cRQ+q1QZkMgI4OAzjpGRgYIBPFZGHIrnTMYGABXvhv4",
                              channel: "myCh")

        */
        let storyboard = UIStoryboard(name: "MainStoryboard_iPhone", bundle: nil)
        let vc = storyboard.instantiateInitialViewController()!
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
