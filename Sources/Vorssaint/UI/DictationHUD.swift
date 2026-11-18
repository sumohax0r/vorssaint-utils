// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import SwiftUI
import AVFoundation

struct DictationHUD: View {
    @ObservedObject var service: DictationService
    @State private var followTranscript = true
    // Keep even saturated microphone input comfortably inside the 18-point lane.
    private var meterLevel: CGFloat {
        service.level.isFinite ? CGFloat(min(1, max(0, service.level))) : 0
    }
    private var closeOnly: Bool {
        service.state == .review && service.transcript.isEmpty
    }
    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            if service.state == .failed || service.state == .permissionRequired || service.state == .review {
                Text(service.message).font(.caption).multilineTextAlignment(.center).lineLimit(4)
                    .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            } else if service.streaming && (service.state == .recording || service.state == .processing) {
                liveTranscript
            }
            HStack(spacing: 9) {
                Button(action: service.cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 18, height: 18)
                        .contentShape(Circle())
                }
                    .help(DictationStrings.text("cancel"))
                    .accessibilityLabel(DictationStrings.text("cancel"))
                if service.state == .processing || service.state == .loading {
                    ProgressView().controlSize(.small)
                    Text(service.message)
                        .font(.caption)
                        .accessibilityLabel(DictationStrings.text(service.state == .loading ? "loading" : "processingStatus"))
                } else if service.state == .permissionRequired {
                    Button(DictationStrings.text(AVCaptureDevice.authorizationStatus(for: .audio) == .denied ? "microphoneSettings" : "allowMicrophone"), action: service.requestMicrophone).font(.caption)
                } else if service.state == .review {
                    if !service.transcript.isEmpty {
                        Button(DictationStrings.text("copy"), action: service.copyTranscript).font(.caption)
                    }
                } else if service.state == .failed {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                } else {
                    HStack(spacing: 3) {
                        ForEach(0..<5) { index in
                            Capsule().fill(.primary.opacity(0.85))
                                .frame(width: 3, height: 4 + meterLevel * CGFloat([3, 6, 8, 6, 3][index]))
                        }
                    }.frame(width: 44, height: 18)
                        .animation(.easeOut(duration: 0.1), value: service.level)
                        .accessibilityLabel(DictationStrings.text("listening"))
                }
                if service.state == .recording {
                    Button(action: service.finish) {
                        Image(systemName: "stop.fill").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white).frame(width: 18, height: 18)
                            .background(.red, in: Circle())
                    }
                    .help(DictationStrings.text("stop"))
                    .accessibilityLabel(DictationStrings.text("stop"))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, closeOnly ? 6 : 10).padding(.vertical, 6)
            .background(Color(white: 0.09), in: Capsule())
            .foregroundStyle(.white)
        }.padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .preferredColorScheme(.dark)
    }
    private var liveTranscript: some View {
        ScrollViewReader { reader in
            ZStack(alignment: .bottomTrailing) {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(service.transcript.isEmpty ? DictationStrings.text("listening") : service.transcript)
                            .font(.system(size: 13))
                            .foregroundStyle(service.transcript.isEmpty ? .secondary : .primary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        Color.clear.frame(height: 1).id("latest")
                    }
                }
                .simultaneousGesture(DragGesture().onChanged { _ in followTranscript = false })
                .onChange(of: service.transcript) { _, _ in
                    if followTranscript { reader.scrollTo("latest", anchor: .bottom) }
                }
                if !followTranscript {
                    Button("Latest ↓") {
                        followTranscript = true
                        reader.scrollTo("latest", anchor: .bottom)
                    }.font(.caption).buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(height: 94)
            .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 12))
        }
    }

}
