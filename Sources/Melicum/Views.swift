import SwiftUI
import AppKit
import AudioCore
import AudioDSP

// The original logo palette: graphite, cream, and a restrained VU-needle red.
private func paletteColor(_ rgb: UInt32) -> Color {
    Color(red: Double((rgb >> 16) & 255)/255,green: Double((rgb >> 8) & 255)/255,blue: Double(rgb & 255)/255)
}
private let bg = paletteColor(0x18181C)
private let panel = paletteColor(0x24242A)
private let secondary = paletteColor(0xA9A298)
private let cream = paletteColor(0xF3EDE2)
private let brandRed = paletteColor(0xFF5A47)
private let warning = brandRed

@available(macOS 14.2, *)
struct MainView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var updater: AppUpdater
    private let tabs = ["Equalizer","App mixer","Spatial audio","Audio Units","Presets"]
    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    output.padding(.horizontal,22).padding(.top,16).padding(.bottom,12)
                    Rectangle().fill(cream.opacity(0.06)).frame(height: 1).padding(.horizontal,22)
                    volume.padding(.horizontal,22).padding(.vertical,12)
                    AudioSpectrum(meters: model.meters,running: model.running)
                }.instrumentPanel()
                if let error = model.error {
                    HStack(alignment: .top,spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(warning)
                        Text(T(error)).font(.system(size: 12)).fixedSize(horizontal: false,vertical: true)
                        Spacer()
                        Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    }.padding(14).background(warning.opacity(0.1),in: RoundedRectangle(cornerRadius: 10))
                }
                navigation
            }.padding(.horizontal,24)
            ScrollView {
                Group {
                    switch model.tab {
                    case "App mixer": mixer
                    case "Spatial audio": spatial
                    case "Audio Units": effects
                    case "Presets": presets
                    default: equalizer
                    }
                }.padding(.horizontal,24).padding(.top,12).padding(.bottom,20)
            }
            footer
        }.background(bg).foregroundStyle(cream).tint(cream).accentColor(cream)
            .buttonStyle(ControlButtonStyle()).toggleStyle(ConsoleCheckboxStyle())
            .preferredColorScheme(.dark).frame(minWidth: 820,minHeight: 760)
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: Bundle.main.url(forResource: "BrandMark",withExtension: "png").flatMap { NSImage(contentsOf: $0) } ?? NSApplication.shared.applicationIconImage)
                .resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(width: 34,height: 38).accessibilityHidden(true)
            VStack(alignment: .leading,spacing: 4) {
                Text(T("Melicum")).font(.system(size: 21,weight: .semibold)).tracking(-0.5)
                Text(T("YOUR SOUND. YOUR CONTROL.")).font(.system(size: 8,weight: .medium,design: .monospaced)).tracking(1.2).foregroundStyle(secondary)
            }
            Spacer()
            Button { model.toggle() } label: {
                HStack(spacing: 8) {
                    if model.busy { ProgressView().controlSize(.small) }
                    else { Image(systemName: "power").font(.system(size: 12,weight: .semibold)).foregroundStyle(model.running ? brandRed : bg) }
                    Text(T(model.running ? "Disable" : "Enable audio")).font(.system(size: 12,weight: .semibold))
                }.padding(.horizontal,15).padding(.vertical,10)
                    .foregroundStyle(model.running ? cream : bg)
                    .background(model.running ? cream.opacity(0.07) : cream,in: Capsule())
                    .overlay(Capsule().stroke(cream.opacity(model.running ? 0.25 : 0)))
            }.buttonStyle(.plain).disabled(model.busy).keyboardShortcut("p",modifiers: [.command,.shift])
        }.padding(.horizontal,28).padding(.vertical,18)
    }
    private var navigation: some View {
        HStack(spacing: 2) {
            ForEach(Array(tabs.enumerated()),id: \.element) { index,tab in
                Button { model.tab = tab } label: {
                    HStack(spacing: 7) {
                        Image(systemName: ["slider.horizontal.3","square.stack","waveform","puzzlepiece.extension","bookmark"][index]).font(.system(size: 11)).foregroundStyle(model.tab == tab ? cream : secondary)
                        Text(T(tab)).font(.system(size: 12,weight: model.tab == tab ? .semibold : .medium))
                    }.frame(maxWidth: .infinity).padding(.vertical,13)
                        .foregroundStyle(model.tab == tab ? cream : secondary)
                        .overlay(alignment: .bottom) {
                            if model.tab == tab { Capsule().fill(brandRed).frame(width: 28,height: 2) }
                        }
                }.buttonStyle(.plain).accessibilityAddTraits(model.tab == tab ? .isSelected : [])
            }
        }.overlay(alignment: .bottom) { Rectangle().fill(cream.opacity(0.07)).frame(height: 1) }
    }
    private var output: some View {
        HStack(spacing: 16) {
            Menu {
                if model.devices.isEmpty { Text(T("No output connected")) }
                ForEach(model.devices) { device in
                    Button { model.selectOutput(device.uid) } label: {
                        if device.uid == model.settings.outputUID { Label(model.deviceName(device),systemImage: "checkmark") }
                        else { Text(model.deviceName(device) + (device.hdmi ? " · HDMI / DisplayPort" : "") + (device.supported ? "" : " · set to stereo")) }
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: model.selectedDevice?.hdmi == true ? "display" : "hifispeaker")
                        .font(.system(size: 18,weight: .light)).foregroundStyle(brandRed).frame(width: 42,height: 42)
                        .background(cream.opacity(0.07),in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading,spacing: 5) {
                        Text(T("AUDIO OUTPUT")).font(.system(size: 8,weight: .semibold,design: .monospaced)).tracking(1.5).foregroundStyle(secondary)
                        HStack(spacing: 8) {
                            Text(model.selectedDevice.map(model.deviceName) ?? T("No output connected")).font(.system(size: 14,weight: .semibold)).lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 8,weight: .bold)).foregroundStyle(secondary)
                        }
                    }
                }.foregroundStyle(cream).accessibilityElement(children: .combine)
            }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).frame(maxWidth: .infinity,alignment: .leading)
                .disabled(model.busy).accessibilityLabel(T("Audio output"))
                .accessibilityValue(model.selectedDevice.map(model.deviceName) ?? T("No output connected"))
            Spacer(minLength: 12)
            VStack(alignment: .trailing,spacing: 6) {
                Label(T(model.systemVolumeActive ? "MACOS VOLUME SYNCED" : "SOFTWARE VOLUME"),systemImage: model.systemVolumeActive ? "checkmark.circle" : "slider.horizontal.3")
                    .font(.system(size: 8,weight: .medium,design: .monospaced)).tracking(0.6)
                    .foregroundStyle(cream).padding(.horizontal,9).padding(.vertical,6).background(cream.opacity(0.07),in: Capsule())
                if !model.driverInstalled {
                    Button(T("Enable system volume…")) { model.installSystemControl() }.font(.system(size: 10))
                        .help(T("Install the virtual audio device to use the macOS slider and volume keys."))
                } else { Text(T("macOS slider and system volume keys")).font(.system(size: 10)).foregroundStyle(secondary) }
            }
        }
    }
    private var volume: some View {
        HStack(alignment: .center,spacing: 28) {
            VStack(alignment: .leading,spacing: 10) {
                HStack(alignment: .firstTextBaseline,spacing: 6) {
                    Text(T("Volume")).font(.system(size: 11,weight: .medium)).foregroundStyle(secondary)
                    Spacer()
                    Text(model.settings.muted ? "MUTE" : "\(Int((model.settings.volume*100).rounded()))")
                        .font(.system(size: model.settings.muted ? 30 : 42,weight: .light,design: .rounded)).tracking(-2).monospacedDigit().foregroundStyle(cream)
                    if !model.settings.muted { Text(T("%")).font(.system(size: 14,weight: .light)).foregroundStyle(secondary) }
                }
                HStack(spacing: 10) {
                    Button { model.settings.muted.toggle() } label: {
                        Image(systemName: model.settings.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 13)).foregroundStyle(model.settings.muted ? warning : cream)
                            .frame(width: 30,height: 30).background(cream.opacity(0.05),in: Circle())
                    }.buttonStyle(.plain).help(T("Mute · ⌘M")).keyboardShortcut("m",modifiers: .command).accessibilityLabel(T("Mute"))
                    Slider(value: $model.settings.volume,in: 0...1).controlSize(.large).accessibilityLabel(T("Master volume"))
                }
                HStack { Text(T("0%")); Spacer(); Text(T("50%")); Spacer(); Text(T("100%")) }
                    .font(.system(size: 8,design: .monospaced)).foregroundStyle(secondary.opacity(0.7)).padding(.leading,40)
            }.frame(maxWidth: .infinity)
            VStack(spacing: 16) {
                sliderRow("Balance",value: $model.settings.balance,range: -1...1,valueText: abs(model.settings.balance) < 0.02 ? T("Center") : "\(Int(abs(model.settings.balance)*100))% \(model.settings.balance < 0 ? "L" : "R")")
                sliderRow("Boost",value: $model.settings.boost,range: 0...12,valueText: String(format: "+%.1f dB",model.settings.boost))
            }.frame(width: 210).padding(12).background(bg.opacity(0.45),in: RoundedRectangle(cornerRadius: 12))
        }
    }
    private var equalizer: some View {
        VStack(spacing: 12) {
            HStack {
                Toggle(T("Equalizer"),isOn: $model.settings.eqEnabled).toggleStyle(ConsoleSwitchStyle()).font(.system(size: 15,weight: .semibold))
                Spacer()
                ConsoleSegments(title: "EQ mode",selection: Binding(get: { model.eqMode },set: { model.chooseMode($0) }),options: [("Basic","Basic"),("Advanced","Advanced"),("Expert","Expert")]).frame(width: 245)
                Button(T("Reset")) { for i in model.settings.bands.indices { model.settings.bands[i].gain = 0 }; model.settings.preamp = 0 }
            }
            EQCurve(bands: model.settings.eqEnabled ? model.settings.bands : [],rate: model.sampleRate,accent: cream).equatable().frame(height: 132).accessibilityLabel(T("Equalizer frequency response"))
            HStack(spacing: 24) {
                sliderRow("Preamp",value: $model.settings.preamp,range: -24...12,valueText: String(format: "%.1f dB",model.settings.preamp))
                Toggle(T("Peak protection"),isOn: $model.settings.limiter).font(.system(size: 11)).help(T("Clamps output samples to ±0.98. This is not a true-peak limiter."))
                Button { model.importPreset() } label: { Label(T("Import AutoEQ"),systemImage: "square.and.arrow.down") }.font(.system(size: 11))
            }
            if model.eqMode == "Expert" {
                HStack { Text(T("FILTER")).frame(width: 120,alignment: .leading); Text(T("FREQUENCY")).frame(width: 90,alignment: .leading); Text(T("GAIN")).frame(maxWidth: .infinity,alignment: .leading); Text(T("Q")).frame(width: 60); Text("").frame(width: 50) }.font(.system(size: 9,weight: .semibold)).tracking(1).foregroundStyle(secondary)
                ForEach($model.settings.bands) { $band in
                    HStack(spacing: 12) {
                        Menu { ForEach(FilterType.allCases) { type in Button(T(type.title)) { band.type = type } } } label: { ConsoleMenuLabel(title: T(band.type.title)) }
                            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).frame(width: 120).accessibilityLabel(T("Filter type")).accessibilityValue(T(band.type.title))
                        TextField(T("Hz"),value: bounded($band.frequency,10...22000),format: .number.precision(.fractionLength(0))).consoleField().frame(width: 70); Text(T("Hz")).font(.system(size: 9)).foregroundStyle(secondary)
                        Slider(value: $band.gain,in: -30...30).accessibilityLabel(F("Gain %d Hz",Int(band.frequency)))
                        TextField(T("dB"),value: bounded($band.gain,-30...30),format: .number.precision(.fractionLength(1))).consoleField().frame(width: 52)
                        TextField(T("Q"),value: bounded($band.q,0.1...20),format: .number.precision(.fractionLength(2))).consoleField().frame(width: 60)
                        Toggle(T("Enabled"),isOn: $band.enabled).labelsHidden().toggleStyle(ConsoleCheckboxStyle(showsLabel: false))
                        Button { model.settings.bands.removeAll { $0.id == band.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).foregroundStyle(secondary).help(T("Remove filter"))
                    }.font(.system(size: 11))
                }
                HStack { Button { model.settings.bands.append(EQBand()) } label: { Label(T("Add band"),systemImage: "plus") }.disabled(model.settings.bands.count >= 64); Spacer(); Text(F("%d / 64 bands",model.settings.bands.count)).font(.system(size: 10,design: .monospaced)).foregroundStyle(secondary) }
            } else {
                HStack(alignment: .top,spacing: 8) {
                    ForEach($model.settings.bands) { $band in
                        VStack(spacing: 10) {
                            Text(String(format: "%+.1f",band.gain)).font(.system(size: 11,design: .monospaced)).foregroundStyle(cream)
                            Slider(value: $band.gain,in: -18...18).frame(width: 100).rotationEffect(.degrees(-90)).frame(width: model.eqMode == "Basic" ? 110 : 45,height: 110)
                            Text(band.frequency >= 1000 ? String(format: "%.0fk",band.frequency/1000) : "\(Int(band.frequency))").font(.system(size: 10,design: .monospaced)).foregroundStyle(secondary)
                        }.frame(maxWidth: .infinity)
                    }
                }.padding(.vertical,8)
            }
        }.padding(22).instrumentPanel()
    }
    private var mixer: some View {
        VStack(alignment: .leading,spacing: 18) {
            sectionTitle("Per-app mixer",subtitle: "Each app keeps its own level. Release the slider to update the audio path.")
            if model.applications.isEmpty { Text(T("Open an app and play audio to see it here.")).foregroundStyle(secondary) }
            ForEach(model.applications) { app in
                HStack(spacing: 14) {
                    Image(systemName: app.playing ? "waveform" : "app").foregroundStyle(app.playing ? cream : secondary).frame(width: 20)
                    Text(app.name).font(.system(size: 12)).frame(width: 170,alignment: .leading).lineLimit(1)
                    Slider(value: Binding(get: { model.settings.appVolumes[app.id] ?? 1 },set: { model.appVolume(app.id,$0,commit: false) }),in: 0...1,onEditingChanged: { if !$0 { model.restart() } }).accessibilityLabel("Volume \(app.name)")
                    Text("\(Int((model.settings.appVolumes[app.id] ?? 1)*100))%").font(.system(size: 11,design: .monospaced)).frame(width: 45)
                    Button { model.appVolume(app.id,(model.settings.appVolumes[app.id] ?? 1) > 0 ? 0 : 1,commit: true) } label: { Image(systemName: model.settings.appVolumes[app.id] == 0 ? "speaker.slash" : "speaker.wave.1") }.buttonStyle(.plain).help("Mute \(app.name)")
                }
            }
        }.padding(22).instrumentPanel()
    }
    private var spatial: some View {
        VStack(alignment: .leading,spacing: 22) {
            HStack { sectionTitle("Spatial audio",subtitle: "Stereo reverb and soundstage width."); Spacer(); Toggle(T("Spatial audio"),isOn: $model.settings.spatialEnabled).labelsHidden().toggleStyle(ConsoleSwitchStyle(showsLabel: false)) }
            ConsoleSegments(title: "Space",selection: $model.settings.room,options: [(0,"Small room"),(1,"Studio"),(2,"Hall"),(3,"Auditorium"),(4,"Cathedral")])
            sliderRow("Reverb mix",value: $model.settings.wet,range: 0...1,valueText: "\(Int(model.settings.wet*100))%")
            sliderRow("Stereo width",value: $model.settings.width,range: 0...2,valueText: "\(Int(model.settings.width*100))%")
        }.padding(22).instrumentPanel()
    }
    private var effects: some View {
        VStack(alignment: .leading,spacing: 18) {
            HStack {
                sectionTitle("Audio Unit effects",subtitle: "Installed effects run after EQ and space, before master volume.")
                Spacer()
                Menu { ForEach(model.effectsAvailable.filter { candidate in !model.settings.effects.contains(where: { $0.id == candidate.id }) }) { effect in Button(effect.name) { model.settings.effects.append(effect); model.restart() } } } label: {
                    Label(T("Add"),systemImage: "plus").font(.system(size: 11,weight: .medium)).padding(.horizontal,12).padding(.vertical,8)
                        .background(cream.opacity(0.05),in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(cream.opacity(0.12)))
                }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().disabled(model.settings.effects.count >= 12)
            }
            if model.settings.effects.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 28,weight: .ultraLight)).foregroundStyle(cream.opacity(0.6))
                    Text(T("No effects in the chain")).font(.system(size: 12)).foregroundStyle(secondary)
                }.frame(maxWidth: .infinity).padding(.vertical,32)
            }
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
        }.padding(22).instrumentPanel()
    }
    private var presets: some View {
        VStack(alignment: .leading,spacing: 18) {
            sectionTitle("Super presets",subtitle: "Save EQ, volume, mixer, space and Audio Unit parameters together.")
            HStack { TextField(T("Preset name"),text: $model.presetName).consoleField(); Button(T("Save")) { model.savePreset() }.disabled(model.presetName.trimmingCharacters(in: .whitespaces).isEmpty); Button(T("Link to output")) { model.savePreset(forDevice: true) }.disabled(model.presetName.trimmingCharacters(in: .whitespaces).isEmpty) }
            HStack {
                Text(T("App for automatic recall")).font(.system(size: 11)).foregroundStyle(secondary)
                Spacer()
                Menu {
                    Button(T("None")) { model.presetAutoApp = "" }
                    ForEach(model.applications) { app in Button(app.name) { model.presetAutoApp = app.id } }
                } label: { ConsoleMenuLabel(title: model.applications.first { $0.id == model.presetAutoApp }?.name ?? T("None")) }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).frame(width: 220).accessibilityLabel(T("App for automatic recall")).accessibilityValue(model.applications.first { $0.id == model.presetAutoApp }?.name ?? T("None"))
            }
            ForEach(model.presets) { preset in
                HStack { Image(systemName: preset.deviceUID != nil ? "display" : "slider.horizontal.3").foregroundStyle(cream); Text(preset.name); if preset.deviceUID != nil { Text(T("AUTO · OUTPUT")).font(.system(size: 8,design: .monospaced)).foregroundStyle(secondary) }; if preset.applicationID != nil { Text(T("AUTO · APP")).font(.system(size: 8,design: .monospaced)).foregroundStyle(secondary) }; Spacer(); Button(T("Apply")) { model.applyPreset(preset) }; Button { model.presets.removeAll { $0.id == preset.id }; model.save() } label: { Image(systemName: "trash") }.buttonStyle(.plain) }.font(.system(size: 12))
            }
            HStack { Button(T("Import JSON / AutoEQ…")) { model.importPreset() }; Button(T("Export settings…")) { model.exportPreset() } }
            Divider()
            HStack {
                Text(T("Language")).font(.system(size: 12))
                Spacer()
                Menu {
                    ForEach(["en","it","fr","de","es"],id: \.self) { code in
                        Button(languageName(code)) { model.language = code }
                    }
                } label: { ConsoleMenuLabel(title: languageName(model.language)) }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).frame(width: 150).accessibilityLabel(T("Language")).accessibilityValue(languageName(model.language))
            }
            Toggle(T("Launch at login"),isOn: $model.launchAtLogin).onChange(of: model.launchAtLogin) { model.loginChanged() }.font(.system(size: 12))
            Toggle(T("Enable audio on launch"),isOn: $model.enableAudioOnLaunch).font(.system(size: 12))
            Text(T("Automatically enable the saved output when Melicum opens. If it is unavailable, audio stays off.")).font(.system(size: 10)).foregroundStyle(secondary)
            Divider()
            HStack {
                Text(T("Updates")).font(.system(size: 12,weight: .semibold))
                Spacer()
                Button(T("Check for Updates…")) { updater.checkForUpdates() }.disabled(!updater.canCheckForUpdates)
            }
            Toggle(T("Automatically check for updates"),isOn: Binding(get: { updater.automaticallyChecksForUpdates },set: { updater.setAutomaticChecks($0) })).font(.system(size: 12))
            Text(T("Checks GitHub for new releases and asks before downloading and installing.")).font(.system(size: 10)).foregroundStyle(secondary)
        }.padding(22).instrumentPanel()
    }
    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(model.running ? brandRed : secondary.opacity(0.5)).frame(width: 6,height: 6)
            Text(model.message).font(.system(size: 10)).foregroundStyle(secondary).lineLimit(1)
            Spacer()
            if model.running { Text("\(Int(model.sampleRate/1000)) kHz · PCM stereo").font(.system(size: 9,design: .monospaced)).foregroundStyle(secondary) }
            Button { model.enableMediaKeys() } label: { Label(T(model.systemVolumeActive ? "macOS volume" : model.mediaKeysEnabled ? "Volume keys enabled" : "Volume keys"),systemImage: "keyboard") }.font(.system(size: 10)).buttonStyle(.borderless).disabled(!model.running)
        }.padding(.horizontal,26).padding(.vertical,12).overlay(alignment: .top) { Rectangle().fill(cream.opacity(0.06)).frame(height: 1) }
    }
    private func languageName(_ code: String) -> String {
        ["en": "English","it": "Italiano","fr": "Français","de": "Deutsch","es": "Español"][code] ?? "English"
    }
    private func sectionTitle(_ title: String,subtitle: String) -> some View { VStack(alignment: .leading,spacing: 5) { Text(T(title)).font(.system(size: 17,weight: .semibold)).tracking(-0.3); Text(T(subtitle)).font(.system(size: 11)).foregroundStyle(secondary).fixedSize(horizontal: false,vertical: true) } }
    private func sliderRow(_ title: String,value: Binding<Double>,range: ClosedRange<Double>,valueText: String) -> some View { VStack(spacing: 6) { HStack { Text(T(title)).foregroundStyle(secondary); Spacer(); Text(valueText).monospacedDigit() }.font(.system(size: 11)); Slider(value: value,in: range).controlSize(.small).accessibilityLabel(T(title)) } }
    private func bounded(_ source: Binding<Double>,_ range: ClosedRange<Double>) -> Binding<Double> { Binding(get: { source.wrappedValue },set: { if $0.isFinite { source.wrappedValue = min(range.upperBound,max(range.lowerBound,$0)) } }) }
}

private struct AudioSpectrum: View {
    @ObservedObject var meters: AudioMeters
    var running: Bool
    private var signal: Bool { running && max(meters.levels.left,meters.levels.right) > 0.0001 }

    var body: some View {
        VStack(alignment: .leading,spacing: 8) {
            HStack {
                Label(T("OUTPUT SPECTRUM"),systemImage: "waveform.path").font(.system(size: 9,weight: .semibold)).tracking(1).foregroundStyle(secondary)
                Spacer()
                Circle().fill(signal ? brandRed : secondary.opacity(0.4)).frame(width: 5,height: 5)
                Text(T(running ? (signal ? "SIGNAL" : "WAITING FOR AUDIO") : "OFF")).font(.system(size: 8,design: .monospaced)).foregroundStyle(secondary).lineLimit(1)
            }
            Canvas { ctx,size in
                let step = size.width/64
                for i in 0..<64 {
                    let value = running ? max(0,min(1,(Double(meters.levels.spectrum[i])+90)/90)) : 0
                    let height = max(2,value*size.height)
                    let rect = CGRect(x: Double(i)*step,y: size.height-height,width: max(1,step-3),height: height)
                    ctx.fill(Path(roundedRect: rect,cornerRadius: 1.5),with: .color(cream.opacity(value > 0.03 ? 0.85 : 0.13)))
                }
            }.frame(height: 20).accessibilityLabel(T("Live audio spectrum analyzer"))
            HStack { Text(T("20 Hz")); Spacer(); Text(T("100")); Spacer(); Text(T("1k")); Spacer(); Text(T("10k")); Spacer(); Text(T("20k Hz")) }.font(.system(size: 8,design: .monospaced)).foregroundStyle(secondary)
        }.padding(.horizontal,22).padding(.vertical,10).background(bg.opacity(0.35))
    }
}

struct EQCurve: View, Equatable {
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
            let active = bands.filter(\.enabled)
            var path = Path()
            for i in 0...240 {
                let hz = 20*pow(1000,Double(i)/240)
                let db = active.reduce(0.0) { $0 + eq_response(Int32($1.type.rawValue),$1.frequency,$1.gain,$1.q,rate,hz) }
                let p = CGPoint(x: size.width*Double(i)/240,y: size.height*(0.5-max(-24,min(24,db))/48))
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            var area = path
            area.addLine(to: CGPoint(x: size.width,y: size.height))
            area.addLine(to: CGPoint(x: 0,y: size.height))
            area.closeSubpath()
            ctx.fill(area,with: .linearGradient(Gradient(colors: [accent.opacity(0.09),accent.opacity(0.01)]),startPoint: .zero,endPoint: CGPoint(x: 0,y: size.height)))
            ctx.stroke(path,with: .color(accent),style: StrokeStyle(lineWidth: 2,lineCap: .round,lineJoin: .round))
            for band in bands where band.enabled {
                let x = log(band.frequency/20)/log(1000)*size.width,y = size.height*(0.5-max(-24,min(24,band.gain))/48)
                let node = Path(ellipseIn: CGRect(x: x-4,y: y-4,width: 8,height: 8))
                ctx.fill(node,with: .color(bg))
                ctx.stroke(node,with: .color(brandRed.opacity(0.85)),lineWidth: 1.5)
            }
        }.padding(12).background(bg.opacity(0.6),in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(cream.opacity(0.04)))
    }
}

private struct ConsoleSegments<Value: Hashable>: View {
    var title: String
    @Binding var selection: Value
    var options: [(Value,String)]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(options.indices,id: \.self) { index in
                Button { selection = options[index].0 } label: {
                    Text(T(options[index].1)).font(.system(size: 11,weight: .medium))
                        .frame(maxWidth: .infinity).padding(.horizontal,9).padding(.vertical,7)
                        .foregroundStyle(selection == options[index].0 ? cream : secondary)
                        .background(selection == options[index].0 ? cream.opacity(0.1) : .clear,in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selection == options[index].0 ? cream.opacity(0.2) : .clear))
                        .overlay(alignment: .bottom) {
                            if selection == options[index].0 { Capsule().fill(brandRed).frame(width: 12,height: 1.5) }
                        }
                }.buttonStyle(.plain)
            }
        }.padding(3).background(bg.opacity(0.45),in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(cream.opacity(0.06)))
            .accessibilityRepresentation {
                Picker(T(title),selection: $selection) {
                    ForEach(options.indices,id: \.self) { index in Text(T(options[index].1)).tag(options[index].0) }
                }.pickerStyle(.segmented)
            }
    }
}

private struct ConsoleMenuLabel: View {
    var title: String
    var body: some View {
        HStack(spacing: 8) {
            Text(title).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8,weight: .semibold)).foregroundStyle(secondary)
        }.font(.system(size: 11)).foregroundStyle(cream).padding(.horizontal,10).padding(.vertical,7)
            .background(bg.opacity(0.5),in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(cream.opacity(0.1)))
            .accessibilityElement(children: .combine)
    }
}

private struct ConsoleFieldStyle: ViewModifier {
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        content.textFieldStyle(.plain).focused($focused).padding(.horizontal,9).padding(.vertical,7)
            .background(bg.opacity(0.5),in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(focused ? cream.opacity(0.7) : cream.opacity(0.1)))
    }
}

private extension View {
    func consoleField() -> some View { modifier(ConsoleFieldStyle()) }
    func instrumentPanel() -> some View {
        background(LinearGradient(colors: [panel, panel.opacity(0.78)],startPoint: .topLeading,endPoint: .bottomTrailing),in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(LinearGradient(colors: [cream.opacity(0.12),cream.opacity(0.035)],startPoint: .topLeading,endPoint: .bottomTrailing)))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.12),radius: 12,x: 0,y: 5)
    }
}

private struct ControlButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal,12).padding(.vertical,7)
            .foregroundStyle(cream)
            .background(cream.opacity(configuration.isPressed ? 0.14 : hovered ? 0.085 : 0.04),in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(hovered ? cream.opacity(0.4) : cream.opacity(0.1)))
            .opacity(isEnabled ? 1 : 0.35)
            .onHover { hovered = $0 }
    }
}

private struct ConsoleCheckboxStyle: ToggleStyle {
    var showsLabel = true
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(configuration.isOn ? cream : bg.opacity(0.5))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(cream.opacity(configuration.isOn ? 0 : 0.22)))
                    .overlay {
                        if configuration.isOn { Image(systemName: "checkmark").font(.system(size: 9,weight: .bold)).foregroundStyle(bg) }
                    }.frame(width: 15,height: 15)
                if showsLabel { configuration.label.foregroundStyle(cream) }
            }.contentShape(Rectangle()).opacity(isEnabled ? 1 : 0.35)
        }.buttonStyle(.plain)
            .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.checkbox) }
    }
}

private struct ConsoleSwitchStyle: ToggleStyle {
    var showsLabel = true
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 10) {
                if showsLabel { configuration.label }
                Capsule().fill(configuration.isOn ? cream : bg)
                    .overlay(Capsule().stroke(cream.opacity(configuration.isOn ? 0 : 0.2)))
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(configuration.isOn ? bg : secondary).frame(width: 12,height: 12).padding(3)
                    }.frame(width: 32,height: 18)
            }.contentShape(Rectangle()).opacity(isEnabled ? 1 : 0.35)
        }.buttonStyle(.plain)
            .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch) }
    }
}

@available(macOS 14.2, *)
struct MenuView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var updater: AppUpdater
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack(alignment: .leading,spacing: 18) {
            HStack(spacing: 8) {
                Image(nsImage: Bundle.main.url(forResource: "BrandMark",withExtension: "png").flatMap { NSImage(contentsOf: $0) } ?? NSApplication.shared.applicationIconImage)
                    .resizable().aspectRatio(contentMode: .fit).frame(width: 22,height: 28).accessibilityHidden(true)
                Text(T("Melicum")).font(.system(size: 16,weight: .semibold)).tracking(-0.3)
                Spacer()
                Circle().fill(model.running ? brandRed : secondary.opacity(0.4)).frame(width: 5,height: 5)
            }
            VStack(alignment: .leading,spacing: 12) {
                Text(model.selectedDevice?.name ?? T("No output")).font(.system(size: 11,weight: .medium)).foregroundStyle(secondary).lineLimit(1)
                HStack(alignment: .firstTextBaseline,spacing: 3) {
                    Text(model.settings.muted ? "MUTE" : "\(Int((model.settings.volume*100).rounded()))")
                        .font(.system(size: 38,weight: .light,design: .rounded)).tracking(-1.5).monospacedDigit().foregroundStyle(cream)
                    if !model.settings.muted { Text(T("%")).font(.system(size: 12)).foregroundStyle(secondary) }
                    Spacer()
                    Button { model.settings.muted.toggle() } label: {
                        Image(systemName: model.settings.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .foregroundStyle(model.settings.muted ? warning : cream).frame(width: 30,height: 30)
                            .background(cream.opacity(0.05),in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel(T("Mute"))
                }
                Slider(value: $model.settings.volume,in: 0...1).accessibilityLabel(T("Master volume"))
            }
            HStack(spacing: 10) {
                Button { model.toggle() } label: { Image(systemName: "power").frame(width: 18) }
                    .disabled(model.busy).accessibilityLabel(T(model.running ? "Disable" : "Enable audio"))
                Button { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) } label: {
                    HStack { Text(T("Open panel")); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 10,weight: .semibold)) }
                        .font(.system(size: 11,weight: .semibold)).padding(.horizontal,12).padding(.vertical,9)
                        .foregroundStyle(bg).background(cream,in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }
            Rectangle().fill(cream.opacity(0.08)).frame(height: 1)
            HStack {
                Button { updater.checkForUpdates() } label: { Label(T("Check for Updates…"),systemImage: "arrow.triangle.2.circlepath") }
                    .disabled(!updater.canCheckForUpdates)
                Spacer()
                Button(T("Quit")) { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(secondary)
        }.padding(20).frame(width: 280).background(bg).foregroundStyle(cream).tint(cream).accentColor(cream)
            .buttonStyle(ControlButtonStyle()).preferredColorScheme(.dark)
    }
}
