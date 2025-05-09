/// Copyright 2025 North Pole Security, Inc.
///
/// Licensed under the Apache License, Version 2.0 (the "License");
/// you may not use this file except in compliance with the License.
/// You may obtain a copy of the License at
///
///     https://www.apache.org/licenses/LICENSE-2.0
///
/// Unless required by applicable law or agreed to in writing, software
/// distributed under the License is distributed on an "AS IS" BASIS,
/// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
/// See the License for the specific language governing permissions and
/// limitations under the License.

import SwiftUI

import santa_common_SNTBlockMessage
import santa_common_SNTCommonEnums
import santa_common_SNTConfigurator
import santa_common_SNTStoredEvent
import santa_gui_SNTMessageView

@objc public class SNTKillOnStartupWindowViewFactory: NSObject {
  @objc public static func createWith(
    window: NSWindow,
    events: [SNTKillEvent],
    customMsg: NSString?,
    customURL: NSString?,
    terminateProcessCallback: ((NSNumber, NSNumber) -> Bool)?
  ) -> NSViewController {
    return NSHostingController(
      rootView: SNTKillOnStartupWindowView(
        window: window,
        events: events,
        customMsg: customMsg,
        customURL: customURL,
        terminateProcessCallback: terminateProcessCallback
      )
      .fixedSize()
    )
  }
}

struct SNTKillOnStartupEventView: View {
  let event: SNTStoredEvent?
  let gracePeriod: Int
  let terminateProcessCallback: ((NSNumber, NSNumber) -> Bool)?

  @State private var isTerminated = false

  var body: some View {
    if let event = event {
      HStack {
        VStack(alignment: .leading) {
          Text(event.filePath as String)
            .font(.body)
            .lineLimit(1)
            .truncationMode(.middle)

          Text("Grace Period: \(gracePeriod)")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Spacer()

        HStack {
          Button(isTerminated ? "Closed" : "Close") {
            if let callback = terminateProcessCallback {
              let success = callback(event.pid, event.pidversion)
              isTerminated = success
            }
          }
          .disabled(gracePeriod == 0 || isTerminated)
          .buttonStyle(.borderedProminent)
          .tint(isTerminated ? .gray : .red)
        }
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      EmptyView()
    }
  }
}

struct SNTKillOnStartupEventViewAnim: View {
  let event: SNTStoredEvent?
  let gracePeriod: Int
  let terminateProcessCallback: ((NSNumber, NSNumber) -> Bool)?

  @State private var isTerminated = false
  @State private var showCloseStatus = false;

  var body: some View {
    if let event = event {
      HStack {
        VStack(alignment: .leading) {
          Text(event.filePath as String)
            .font(.body)
            .lineLimit(1)
            .truncationMode(.middle)

          Text("Grace Period: \(gracePeriod)")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Spacer()

        HStack {
          Button(isTerminated ? "Closed" : "Close") {
            if let callback = terminateProcessCallback {
              let success = callback(event.pid, event.pidversion)
              isTerminated = success

              withAnimation {
                showCloseStatus = true
              }

              // Hide after 1 second
              DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                withAnimation {
                  showCloseStatus = false
                }
              }
            }
          }
          .disabled(gracePeriod == 0 || isTerminated)
          .buttonStyle(.borderedProminent)
          .tint(isTerminated ? .gray : .red)

          ZStack {
            Image(systemName: "checkmark.circle.fill")
              .foregroundColor(.clear)

            if showCloseStatus {
              if isTerminated {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundColor(.blue)
                  .transition(.opacity)
              } else {
                Image(systemName: "x.circle.fill")
                  .foregroundColor(.red)
                  .transition(.opacity)
              }
            }
          }
        }
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      EmptyView()
    }
  }
}

struct SNTKillOnStartupAllEventsView: View {
  let events: [SNTKillEvent]
  let terminateProcessCallback: ((NSNumber, NSNumber) -> Bool)?

  var body: some View {
    VStack(spacing: 8) {
      ForEach(Array(zip(events.indices, events)), id: \.0) { index, event in
        SNTKillOnStartupEventView(
          event: event.event,
          gracePeriod: event.gracePeriod,
          terminateProcessCallback: terminateProcessCallback
        )
      }
    }
    .padding()
  }
}

struct SNTKillOnStartupWindowView: View {
  let window: NSWindow?
  let events: [SNTKillEvent]
  let customMsg: NSString?
  let customURL: NSString?
  let terminateProcessCallback: ((NSNumber, NSNumber) -> Bool)?

  @Environment(\.openURL) var openURL

  let c = SNTConfigurator.configurator()

  var body: some View {
    SNTMessageView(
      SNTBlockMessage.attributedBlockMessage(for: nil, customMessage: customMsg as String?)
    ) {
      VStack {
        SNTKillOnStartupAllEventsView(events: events, terminateProcessCallback: terminateProcessCallback)

        DismissButton(
          customText: nil,
          silence: nil,
          action: dismissButton
        )
      }
    }.fixedSize()
  }

  func dismissButton() {
    window?.close()
  }
}
