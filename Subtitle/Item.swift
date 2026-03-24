//
//  Item.swift
//  Subtitle
//
//  Created by nelson.wu on 2026/3/24.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
