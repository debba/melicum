import SwiftUI
import AppKit
import AudioCore
import AudioDSP

// Fixed "Vinyl and VU" palette from the logo: graphite, cream, and VU-needle red.
private let bg = Color(red: 0.094,green: 0.094,blue: 0.110)
private let panel = Color(red: 0.141,green: 0.141,blue: 0.165)
private let secondary = Color(red: 0.612,green: 0.588,blue: 0.553)
private let cream = Color(red: 0.953,green: 0.929,blue: 0.886)
private let accent = Color(red: 1,green: 0.353,blue: 0.278)

@available(macOS 14.2, *)
struct MainView: View {
    @EnvironmentObject var model: AppModel
    private let tabs = ["Equalizer","App mixer","Spatial audio","Audio Units","Presets"]
    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 18) {
                    output
                    volume
                    if let error = model.error {
                        HStack(alignment: .top,spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text(T(error)).font(.system(size: 12)).fixedSize(horizontal: false,vertical: true)
                            Spacer(); Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                        }.padding(14).background(Color.orange.opacity(0.1),in: RoundedRectangle(cornerRadius: 12))
                    }
                    spectrum
                    HStack(spacing: 4) {
                        ForEach(tabs,id: \.self) { tab in
                            Button { model.tab = tab } label: {
                                Text(T(tab)).font(.system(size: 12,weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical,10)
                                    .background(model.tab == tab ? accent.opacity(0.16) : Color.clear,in: RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(model.tab == tab ? accent : secondary)
                            }.buttonStyle(.plain)
                        }
                    }.padding(4).background(panel,in: RoundedRectangle(cornerRadius: 12))
                    Group {
                        switch model.tab {
                        case "App mixer": mixer
                        case "Spatial audio": spatial
                        case "Audio Units": effects
                        case "Presets": presets
                        default: equalizer
                        }
                    }
                }.padding(24)
            }
            footer
        }.background(bg).foregroundStyle(cream).tint(accent).preferredColorScheme(.dark)
            .frame(minWidth: 820,minHeight: 760)
    }
    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: Bundle.main.url(forResource: "BrandMark",withExtension: "png").flatMap { NSImage(contentsOf: $0) } ?? NSApplication.shared.applicationIconImage).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(width: 60,height: 46).accessibilityHidden(true)
            VStack(alignment: .leading,spacing: 3) { Text(T("Melicum")).font(.system(size: 20,weight: .semibold)); Text(T("YOUR SOUND. YOUR CONTROL.")).font(.system(size: 9,weight: .medium,design: .monospaced)).tracking(1.5).foregroundStyle(secondary) }
            Spacer()
            Text(T("MACOS · LOCAL")).font(.system(size: 9,weight: .semibold,design: .monospaced)).tracking(1).foregroundStyle(secondary).padding(8).overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.1)))
            Button { model.toggle() } label: {
                HStack { if model.busy { ProgressView().controlSize(.small) } else { Image(systemName: "power") }; Text(T(model.running ? "Disable" : "Enable audio")).fontWeight(.semibold) }
                    .padding(.horizontal,16).padding(.vertical,10).background(model.running ? accent.opacity(0.13) : accent,in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(model.running ? accent : bg)
            }.buttonStyle(.plain).disabled(model.busy).keyboardShortcut("p",modifiers: [.command,.shift])
        }.padding(.horizontal,24).padding(.vertical,18).background(panel.opacity(0.45))
    }
    private var output: some View {
        HStack(spacing: 12) {
            Image(systemName: model.selectedDevice?.hdmi == true ? "display" : "hifispeaker").foregroundStyle(accent).font(.title2)
            VStack(alignment: .leading,spacing: 6) {
                Text(T("AUDIO OUTPUT")).font(.system(size: 9,weight: .semibold)).tracking(1.4).foregroundStyle(secondary)
                Picker(T("Audio output"),selection: Binding(get: { model.settings.outputUID },set: { model.selectOutput($0) })) {
                    if model.devices.isEmpty { Text(T("No output connected")).tag("") }
                    ForEach(model.devices) { d in Text(model.deviceName(d) + (d.hdmi ? " · HDMI / DisplayPort" : "") + (d.supported ? "" : " · set to stereo")).tag(d.uid) }
                }.labelsHidden().frame(maxWidth: 400).disabled(model.busy)
            }
            Spacer()
            VStack(alignment: .trailing,spacing: 5) {
                Text(T(model.systemVolumeActive ? "MACOS VOLUME SYNCED" : "SOFTWARE VOLUME")).font(.system(size: 10,weight: .semibold)).tracking(1).foregroundStyle(accent)
                if !model.driverInstalled { Button(T("Enable system volume…")) { model.installSystemControl() }.font(.system(size: 11)).help(T("Install the virtual audio device to use the macOS slider and volume keys.")) }
                else { Text(T("macOS slider and system volume keys")).font(.system(size: 11)).foregroundStyle(secondary) }
            }
        }.padding(16).background(panel,in: RoundedRectangle(cornerRadius: 12))
    }
    private var volume: some View {
        HStack(alignment: .top,spacing: 24) {
            VStack(alignment: .leading,spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(T("Volume")).font(.system(size: 13,weight: .medium)).foregroundStyle(secondary)
                    Spacer()
                    Text(model.settings.muted ? "MUTE" : "\(Int((model.settings.volume*100).rounded()))").font(.system(size: 38,weight: .light,design: .rounded)).monospacedDigit()
                    if !model.settings.muted { Text(T("%")).font(.system(size: 15)).foregroundStyle(secondary) }
                }
                HStack(spacing: 12) {
                    Button { model.settings.muted.toggle() } label: { Image(systemName: model.settings.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.system(size: 16)).frame(width: 30).foregroundStyle(model.settings.muted ? .orange : accent) }.buttonStyle(.plain).help(T("Mute · ⌘M")).keyboardShortcut("m",modifiers: .command).accessibilityLabel(T("Mute"))
                    Slider(value: $model.settings.volume,in: 0...1).accessibilityLabel(T("Master volume"))
                }
                HStack { Text(T("0%")); Spacer(); Text(T("50%")); Spacer(); Text(T("100%")) }.font(.system(size: 9,design: .monospaced)).foregroundStyle(secondary)
            }.frame(maxWidth: .infinity)
            Rectangle().fill(.white.opacity(0.07)).frame(width: 1,height: 112)
            VStack(alignment: .leading,spacing: 16) {
                sliderRow("Balance",value: $model.settings.balance,range: -1...1,valueText: abs(model.settings.balance) < 0.02 ? T("Center") : "\(Int(abs(model.settings.balance)*100))% \(model.settings.balance < 0 ? "L" : "R")")
                sliderRow("Boost",value: $model.settings.boost,range: 0...12,valueText: String(format: "+%.1f dB",model.settings.boost))
            }.frame(width: 230)
        }.padding(20).background(panel,in: RoundedRectangle(cornerRadius: 12))
    }
    private var spectrum: some View {
        VStack(alignment: .leading,spacing: 8) {
            HStack { Label(T("OUTPUT SPECTRUM"),systemImage: "waveform.path").font(.system(size: 9,weight: .semibold)).tracking(1).foregroundStyle(secondary); Spacer(); Circle().fill(model.running && max(model.left,model.right) > 0.0001 ? accent : secondary.opacity(0.4)).frame(width: 5,height: 5); Text(T(model.running ? (max(model.left,model.right) > 0.0001 ? "SIGNAL" : "WAITING FOR AUDIO") : "OFF")).font(.system(size: 8,design: .monospaced)).foregroundStyle(secondary) }
            GeometryReader { geo in
                Canvas { ctx,size in
                    let step = size.width/64
                    for i in 0..<64 {
                        let value = model.running ? max(0,min(1,(Double(model.spectrum[i])+90)/90)) : 0
                        let h = max(2,value*size.height)
                        let rect = CGRect(x: Double(i)*step,y: size.height-h,width: max(1,step-3),height: h)
                        ctx.fill(Path(roundedRect: rect,cornerRadius: 1.5),with: .color(accent.opacity(value > 0.03 ? 0.7 : 0.13)))
                    }
                }
            }.frame(height: 64).accessibilityLabel(T("Live audio spectrum analyzer"))
            HStack { Text(T("20 Hz")); Spacer(); Text(T("100")); Spacer(); Text(T("1k")); Spacer(); Text(T("10k")); Spacer(); Text(T("20k Hz")) }.font(.system(size: 8,design: .monospaced)).foregroundStyle(secondary)
        }.padding(16).background(panel,in: RoundedRectangle(cornerRadius: 12))
    }
    private var equalizer: some View {
        VStack(spacing: 16) {
            HStack {
                Toggle(T("Equalizer"),isOn: $model.settings.eqEnabled).toggleStyle(.switch).font(.system(size: 13,weight: .medium))
                Spacer()
                Picker(T("EQ mode"),selection: Binding(get: { model.eqMode },set: { model.chooseMode($0) })) { Text(T("Basic")).tag("Basic"); Text(T("Advanced")).tag("Advanced"); Text(T("Expert")).tag("Expert") }.pickerStyle(.segmented).frame(width: 270)
                Button(T("Reset")) { for i in model.settings.bands.indices { model.settings.bands[i].gain = 0 }; model.settings.preamp = 0 }
            }
            EQCurve(bands: model.settings.eqEnabled ? model.settings.bands : [],rate: model.sampleRate,accent: accent).frame(height: 130)
            HStack(spacing: 24) {
                sliderRow("Preamp",value: $model.settings.preamp,range: -24...12,valueText: String(format: "%.1f dB",model.settings.preamp))
                Toggle(T("Peak protection"),isOn: $model.settings.limiter).font(.system(size: 11)).help(T("Clamps output samples to ±0.98. This is not a true-peak limiter."))
                Button { model.importPreset() } label: { Label(T("Import AutoEQ"),systemImage: "square.and.arrow.down") }.font(.system(size: 11))
            }
            if model.eqMode == "Expert" {
                HStack { Text(T("FILTER")).frame(width: 120,alignment: .leading); Text(T("FREQUENCY")).frame(width: 90,alignment: .leading); Text(T("GAIN")).frame(maxWidth: .infinity,alignment: .leading); Text(T("Q")).frame(width: 60); Text("").frame(width: 50) }.font(.system(size: 9,weight: .semibold)).tracking(1).foregroundStyle(secondary)
                ForEach($model.settings.bands) { $band in
                    HStack(spacing: 12) {
                        Picker(T("Filter type"),selection: $band.type) { ForEach(FilterType.allCases) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 120)
                        TextField(T("Hz"),value: bounded($band.frequency,10...22000),format: .number.precision(.fractionLength(0))).textFieldStyle(.roundedBorder).frame(width: 70); Text(T("Hz")).font(.system(size: 9)).foregroundStyle(secondary)
                        Slider(value: $band.gain,in: -30...30).accessibilityLabel(F("Gain %d Hz",Int(band.frequency)))
                        TextField(T("dB"),value: bounded($band.gain,-30...30),format: .number.precision(.fractionLength(1))).textFieldStyle(.roundedBorder).frame(width: 52)
                        TextField(T("Q"),value: bounded($band.q,0.1...20),format: .number.precision(.fractionLength(2))).textFieldStyle(.roundedBorder).frame(width: 60)
                        Toggle(T("Enabled"),isOn: $band.enabled).labelsHidden().toggleStyle(.checkbox)
                        Button { model.settings.bands.removeAll { $0.id == band.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).foregroundStyle(secondary).help(T("Remove filter"))
                    }.font(.system(size: 11))
                }
                HStack { Button { model.settings.bands.append(EQBand()) } label: { Label(T("Add band"),systemImage: "plus") }.disabled(model.settings.bands.count >= 64); Spacer(); Text(F("%d / 64 bands",model.settings.bands.count)).font(.system(size: 10,design: .monospaced)).foregroundStyle(secondary) }
            } else {
                HStack(alignment: .top,spacing: 8) {
                    ForEach($model.settings.bands) { $band in
                        VStack(spacing: 10) {
                            Text(String(format: "%+.1f",band.gain)).font(.system(size: 11,design: .monospaced)).foregroundStyle(accent)
                            Slider(value: $band.gain,in: -18...18).frame(width: 100).rotationEffect(.degrees(-90)).frame(width: model.eqMode == "Basic" ? 110 : 45,height: 110)
                            Text(band.frequency >= 1000 ? String(format: "%.0fk",band.frequency/1000) : "\(Int(band.frequency))").font(.system(size: 10,design: .monospaced)).foregroundStyle(secondary)
                        }.frame(maxWidth: .infinity)
                    }
                }.padding(.vertical,8)
            }
        }.padding(20).background(panel,in: RoundedRectangle(cornerRadius: 12))
    }
    private var mixer: some View {
        VStack(alignment: .leading,spacing: 18) {
            sectionTitle("Per-app mixer",subtitle: "Each app keeps its own level. Release the slider to update the audio path.")
            if model.applications.isEmpty { Text(T("Open an app and play audio to see it here.")).foregroundStyle(secondary) }
            ForEach(model.applications) { app in
                HStack(spacing: 14) {
                    Image(systemName: app.playing ? "waveform" : "app").foregroundStyle(app.playing ? accent : secondary).frame(width: 20)
                    Text(app.name).font(.system(size: 12)).frame(width: 170,alignment: .leading).lineLimit(1)
                    Slider(value: Binding(get: { model.settings.appVolumes[app.id] ?? 1 },set: { model.appVolume(app.id,$0,commit: false) }),in: 0...1,onEditingChanged: { if !$0 { model.restart() } }).accessibilityLabel("Volume \(app.name)")
                    Text("\(Int((model.settings.appVolumes[app.id] ?? 1)*100))%").font(.system(size: 11,design: .monospaced)).frame(width: 45)
                    Button { model.appVolume(app.id,(model.settings.appVolumes[app.id] ?? 1) > 0 ? 0 : 1,commit: true) } label: { Image(systemName: model.settings.appVolumes[app.id] == 0 ? "speaker.slash" : "speaker.wave.1") }.buttonStyle(.plain).help("Mute \(app.name)")
                }
            }
        }.padding(20).background(panel,in: RoundedRectangle(cornerRadius: 12))
    }
    private var spatial: some View {
        VStack(alignment: .leading,spacing: 22) {
            HStack { sectionTitle("Spatial audio",subtitle: "Stereo reverb and soundstage width."); Spacer(); Toggle(T("Spatial audio"),isOn: $model.settings.spatialEnabled).labelsHidden().toggleStyle(.switch) }
            Picker(T("Space"),selection: $model.settings.room) { Text(T("Small room")).tag(0.0); Text(T("Studio")).tag(1.0); Text(T("Hall")).tag(2.0); Text(T("Auditorium")).tag(3.0); Text(T("Cathedral")).tag(4.0) }.pickerStyle(.segmented)
            sliderRow("Reverb mix",value: $model.settings.wet,range: 0...1,valueText: "\(Int(model.settings.wet*100))%")
            sliderRow("Stereo width",value: $model.settings.width,range: 0...2,valueText: "\(Int(model.settings.width*100))%")
        }.padding(20).background(panel,in: RoundedRectangle(cornerRadius: 12))
    }
    private var effects: some View {
        VStack(alignment: .leading,spacing: 18) {
            HStack {
                sectionTitle("Audio Unit effects",subtitle: "Installed effects run after EQ and space, before master volume.")
                Spacer()
                Menu { ForEach(model.effectsAvailable.filter { candidate in !model.settings.effects.contains(where: { $0.id == candidate.id }) }) { effect in Button(effect.name) { model.settings.effects.append(effect); model.restart() } } } label: { Label(T("Add"),systemImage: "plus") }.disabled(model.settings.effects.count >= 12)
            }
            if model.settings.effects.isEmpty { Label(T("No effects in the chain"),systemImage: "square.stack.3d.up").foregroundStyle(secondary).padding(.vertical,16) }
            ForEach($model.settings.effects) { $effect in
                VStack(alignment: .leading,spacing: 12) {
                    HStack { Text(effect.name).font(.system(size: 12,weight: .semibold)); Spacer(); Toggle(T("Enabled"),isOn: $effect.enabled).labelsHidden().onChange(of: effect.enabled) { model.restart() }; Button { model.settings.effects.removeAll { $0.id == effect.id }; model.restart() } label: { Image(systemName: "trash") }.buttonStyle(.plain) }
                    if let params = model.parameters[effect.id], effect.enabled, model.running {
                        ForEach(params) { p in
                            HStack { Text(p.name).font(.system(size: 10)).frame(width: 170,alignment: .leading); Slider(value: Binding(get: { effect.parameters[String(p.id)] ?? p.value },set: { model.setParameter(effectID: effect.id,id: p.id,value: $0) }),in: p.min...p.max); Text(String(format: "%.2f",effect.parameters[String(p.id)] ?? p.value)).font(.system(size: 10,design: .monospaced)).frame(width: 65) }
                        }
                    } else { Text(T("Enable audio to load the effect and edit its parameters.")).font(.system(size: 10)).foregroundStyle(secondary) }
                }.padding(14).background(bg.opacity(0.65),in: RoundedRectangle(cornerRadius: 9))
            }
        }.padding(20).background(panel,in: RoundedRectangle(cornerRadius: 12))
    }
    private var presets: some View {
        VStack(alignment: .leading,spacing: 18) {
            sectionTitle("Super presets",subtitle: "Save EQ, volume, mixer, space and Audio Unit parameters together.")
            HStack { TextField(T("Preset name"),text: $model.presetName).textFieldStyle(.roundedBorder); Button(T("Save")) { model.savePreset() }.disabled(model.presetName.trimmingCharacters(in: .whitespaces).isEmpty); Button(T("Link to output")) { model.savePreset(forDevice: true) }.disabled(model.presetName.trimmingCharacters(in: .whitespaces).isEmpty) }
            Picker(T("App for automatic recall"),selection: $model.presetAutoApp) { Text(T("None")).tag(""); ForEach(model.applications) { Text($0.name).tag($0.id) } }.font(.system(size: 11))
            ForEach(model.presets) { preset in
                HStack { Image(systemName: preset.deviceUID != nil ? "display" : "slider.horizontal.3").foregroundStyle(accent); Text(preset.name); if preset.deviceUID != nil { Text(T("AUTO · OUTPUT")).font(.system(size: 8,design: .monospaced)).foregroundStyle(secondary) }; if preset.applicationID != nil { Text(T("AUTO · APP")).font(.system(size: 8,design: .monospaced)).foregroundStyle(secondary) }; Spacer(); Button(T("Apply")) { model.applyPreset(preset) }; Button { model.presets.removeAll { $0.id == preset.id }; model.save() } label: { Image(systemName: "trash") }.buttonStyle(.plain) }.font(.system(size: 12))
            }
            HStack { Button(T("Import JSON / AutoEQ…")) { model.importPreset() }; Button(T("Export settings…")) { model.exportPreset() } }
            Divider()
            HStack { Text(T("Language")).font(.system(size: 12)); Spacer(); Picker(T("Language"),selection: $model.language) { Text("English").tag("en"); Text("Italiano").tag("it"); Text("Français").tag("fr"); Text("Deutsch").tag("de"); Text("Español").tag("es") }.labelsHidden().frame(width: 150) }
            Toggle(T("Launch at login"),isOn: $model.launchAtLogin).onChange(of: model.launchAtLogin) { model.loginChanged() }.font(.system(size: 12))
            Toggle(T("Enable audio on launch"),isOn: $model.enableAudioOnLaunch).font(.system(size: 12))
            Text(T("Automatically enable the saved output when Melicum opens. If it is unavailable, audio stays off.")).font(.system(size: 10)).foregroundStyle(secondary)
        }.padding(20).background(panel,in: RoundedRectangle(cornerRadius: 12))
    }
    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(model.running ? accent : secondary.opacity(0.5)).frame(width: 6,height: 6)
            Text(model.message).font(.system(size: 10)).foregroundStyle(secondary).lineLimit(1)
            Spacer()
            if model.running { Text("\(Int(model.sampleRate/1000)) kHz · PCM stereo").font(.system(size: 9,design: .monospaced)).foregroundStyle(secondary) }
            Button { model.enableMediaKeys() } label: { Label(T(model.systemVolumeActive ? "macOS volume" : model.mediaKeysEnabled ? "Volume keys enabled" : "Volume keys"),systemImage: "keyboard") }.font(.system(size: 10)).buttonStyle(.borderless).disabled(!model.running)
        }.padding(.horizontal,24).padding(.vertical,13).background(panel.opacity(0.5))
    }
    private func sectionTitle(_ title: String,subtitle: String) -> some View { VStack(alignment: .leading,spacing: 5) { Text(T(title)).font(.system(size: 15,weight: .medium)); Text(T(subtitle)).font(.system(size: 11)).foregroundStyle(secondary).fixedSize(horizontal: false,vertical: true) } }
    private func sliderRow(_ title: String,value: Binding<Double>,range: ClosedRange<Double>,valueText: String) -> some View { VStack(spacing: 6) { HStack { Text(T(title)).foregroundStyle(secondary); Spacer(); Text(valueText).monospacedDigit() }.font(.system(size: 11)); Slider(value: value,in: range).accessibilityLabel(T(title)) } }
    private func bounded(_ source: Binding<Double>,_ range: ClosedRange<Double>) -> Binding<Double> { Binding(get: { source.wrappedValue },set: { if $0.isFinite { source.wrappedValue = min(range.upperBound,max(range.lowerBound,$0)) } }) }
}

struct EQCurve: View {
    var bands: [EQBand]
    var rate: Double
    var accent: Color
    var body: some View {
        Canvas { ctx,size in
            for db in stride(from: -24,through: 24,by: 12) {
                let y = size.height*(0.5-Double(db)/48)
                var line = Path(); line.move(to: CGPoint(x: 0,y: y)); line.addLine(to: CGPoint(x: size.width,y: y)); ctx.stroke(line,with: .color(.white.opacity(db == 0 ? 0.2 : 0.06)),lineWidth: 1)
                ctx.draw(Text("\(db)").font(.system(size: 8,design: .monospaced)).foregroundColor(secondary),at: CGPoint(x: 12,y: min(size.height-6,max(6,y-6))))
            }
            for hz in [20.0,100,1000,10000,20000] {
                let x = log(hz/20)/log(1000)*size.width
                var line = Path();line.move(to: CGPoint(x: x,y: 0));line.addLine(to: CGPoint(x: x,y: size.height));ctx.stroke(line,with: .color(.white.opacity(0.05)),lineWidth: 1)
            }
            var path = Path()
            for i in 0...240 {
                let hz = 20*pow(1000,Double(i)/240)
                let db = bands.filter(\.enabled).reduce(0.0) { $0 + eq_response(Int32($1.type.rawValue),$1.frequency,$1.gain,$1.q,rate,hz) }
                let p = CGPoint(x: size.width*Double(i)/240,y: size.height*(0.5-max(-24,min(24,db))/48))
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            ctx.stroke(path,with: .color(accent),style: StrokeStyle(lineWidth: 2,lineCap: .round,lineJoin: .round))
            for band in bands where band.enabled {
                let x = log(band.frequency/20)/log(1000)*size.width,y = size.height*(0.5-max(-24,min(24,band.gain))/48)
                ctx.fill(Path(ellipseIn: CGRect(x: x-3,y: y-3,width: 6,height: 6)),with: .color(accent))
            }
        }.padding(10).background(Color.black.opacity(0.18),in: RoundedRectangle(cornerRadius: 8)).accessibilityLabel(T("Equalizer frequency response"))
    }
}

@available(macOS 14.2, *)
struct MenuView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            HStack { Label(T("Melicum"),systemImage: "slider.horizontal.3").font(.headline); Spacer(); Circle().fill(model.running ? accent : secondary).frame(width: 7,height: 7) }
            Text(model.selectedDevice?.name ?? T("No output")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack { Button { model.settings.muted.toggle() } label: { Image(systemName: model.settings.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") }.buttonStyle(.plain); Slider(value: $model.settings.volume,in: 0...1); Text("\(Int(model.settings.volume*100))%").monospacedDigit().frame(width: 36) }
            HStack { Button(T(model.running ? "Disable" : "Enable audio")) { model.toggle() }.disabled(model.busy); Spacer(); Button(T("Open panel")) { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) } }
            Divider(); Button(T("Quit")) { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        }.padding(18).frame(width: 310).tint(accent)
    }
}
