import XCTest
import AudioToolbox
@testable import AudioCore
import AudioDSP

final class DSPTests: XCTestCase {
    func signal(_ d: OpaquePointer, hz: Double = 1000, amplitude: Float = 0.1, blocks: Int = 15) -> (left: [Float],right: [Float]) {
        var l = [Float](repeating: 0,count: 4096),r = l
        for block in 0..<blocks {
            for i in 0..<4096 { l[i] = amplitude*Float(sin(2*Double.pi*hz*Double(block*4096+i)/48000)); r[i] = l[i] }
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in eq_process(d,lp.baseAddress,rp.baseAddress,4096) } }
        }
        return (l,r)
    }
    func rms(_ a: [Float]) -> Double { sqrt(a.reduce(0) { $0+Double($1*$1) }/Double(a.count)) }
    func make(_ gain: Double = 1,pan: Double = 0,limiter: Int32 = 0) -> OpaquePointer {
        let d = eq_create(48000)!; eq_set_controls(d,gain,pan,0,limiter,0,0,1); return d
    }
    func testHDMIVolumeAttenuation() {
        let d = make(0.25); defer { eq_destroy(d) }
        let s = signal(d)
        XCTAssertEqual(rms(s.left),0.1/sqrt(2)*0.25,accuracy: 0.0001)
        XCTAssertEqual(rms(s.left),rms(s.right),accuracy: 0.000001)
    }
    func testMuteSettlesToSilence() {
        let d = make(); defer { eq_destroy(d) }; _ = signal(d)
        eq_set_controls(d,0,0,0,1,0,0,1)
        XCTAssertLessThan(rms(signal(d).left),1e-12)
    }
    func testBalanceSilencesOppositeChannel() {
        let d = make(pan: -1); defer { eq_destroy(d) }
        let s = signal(d); XCTAssertGreaterThan(rms(s.left),0.06); XCTAssertLessThan(rms(s.right),1e-12)
    }
    func testPeakFilterMatchesSixDB() {
        let d = make(); defer { eq_destroy(d) }
        eq_set_band_count(d,1); eq_set_band(d,0,0,1000,6,1,1)
        XCTAssertEqual(rms(signal(d).left)/(0.1/sqrt(2)),pow(10,6.0/20),accuracy: 0.01)
        XCTAssertEqual(eq_response(0,1000,6,1,48000,1000),6,accuracy: 0.001)
    }
    func testLowPassRejectsHighFrequencies() {
        let d = make(); defer { eq_destroy(d) }
        eq_set_band_count(d,1); eq_set_band(d,0,3,500,0,0.707,1)
        let low = rms(signal(d,hz: 100).left),high = rms(signal(d,hz: 8000).left)
        XCTAssertGreaterThan(low/high,100)
    }
    func testSamplePeakProtection() {
        let d = make(16,limiter: 1); defer { eq_destroy(d) }
        let s = signal(d,amplitude: 0.8); XCTAssertLessThanOrEqual(s.left.map(abs).max()!,0.980001)
    }
    func testAllFiltersRemainFiniteAtExtremes() {
        for type in 0...6 {
            let d = make(); eq_set_band_count(d,64)
            for i in 0..<64 { eq_set_band(d,Int32(i),Int32(type),Double(i+1)*300,Double(i%3-1)*6,0.1,1) }
            let s = signal(d,blocks: 3); XCTAssertTrue(s.left.allSatisfy(\.isFinite)); eq_destroy(d)
        }
    }
    func testSpectrumReflectsActualTone() {
        let d = make(); defer { eq_destroy(d) }; _ = signal(d,hz: 1000)
        let bins = (0..<64).map { eq_spectrum(d,Int32($0)) },peak = bins.indices.max(by: { bins[$0] < bins[$1] })!
        let hz = 20*pow(1000,Double(peak)/63)
        XCTAssertTrue((850...1150).contains(hz)); XCTAssertGreaterThan(eq_frames(d),0)
    }
    func testAudioUnitProcessesRealBuffers() throws {
        let d = make(); defer { eq_destroy(d) }
        var desc = AudioComponentDescription(componentType: kAudioUnitType_Effect,componentSubType: kAudioUnitSubType_LowPassFilter,componentManufacturer: kAudioUnitManufacturer_Apple,componentFlags: 0,componentFlagsMask: 0)
        let component = try XCTUnwrap(AudioComponentFindNext(nil,&desc)); var unit: AudioUnit?
        XCTAssertEqual(AudioComponentInstanceNew(component,&unit),noErr)
        let effect = try XCTUnwrap(unit); defer { AudioUnitUninitialize(effect); AudioComponentInstanceDispose(effect) }
        XCTAssertEqual(eq_add_effect(d,effect),noErr)
        XCTAssertEqual(AudioUnitSetParameter(effect,kLowPassParam_CutoffFrequency,kAudioUnitScope_Global,0,500,0),noErr)
        let low = rms(signal(d,hz: 100).left),high = rms(signal(d,hz: 8000).left)
        XCTAssertGreaterThan(low/high,20); XCTAssertEqual(eq_render_error(d),0)
    }
    func testIOProcSelectsTrailingTapAndWritesInterleavedStereo() {
        let d = make(0.25); defer { eq_destroy(d) }; _ = signal(d)
        let input = AudioBufferList.allocate(maximumBuffers: 2),output = AudioBufferList.allocate(maximumBuffers: 1)
        defer { input.unsafeMutablePointer.deallocate(); output.unsafeMutablePointer.deallocate() }
        var mic = [Float](repeating: 0.9,count: 32),tap = [Float](repeating: 0,count: 64),out = tap
        for i in 0..<32 { tap[i*2] = 0.4; tap[i*2+1] = -0.2 }
        mic.withUnsafeMutableBytes { m in tap.withUnsafeMutableBytes { t in out.withUnsafeMutableBytes { o in
            input[0] = AudioBuffer(mNumberChannels: 1,mDataByteSize: UInt32(m.count),mData: m.baseAddress)
            input[1] = AudioBuffer(mNumberChannels: 2,mDataByteSize: UInt32(t.count),mData: t.baseAddress)
            output[0] = AudioBuffer(mNumberChannels: 2,mDataByteSize: UInt32(o.count),mData: o.baseAddress)
            var ts = AudioTimeStamp(); eq_set_tap_buffers(d,1)
            let status = eq_io_proc()(0,&ts,input.unsafePointer,&ts,output.unsafeMutablePointer,&ts,UnsafeMutableRawPointer(d))
            XCTAssertEqual(status,noErr)
        } } }
        XCTAssertEqual(out[0],0.1,accuracy: 0.00001); XCTAssertEqual(out[1],-0.05,accuracy: 0.00001)
    }
    func testIOProcPlanarStereo() {
        let d = make(); defer { eq_destroy(d) }; _ = signal(d)
        let input = AudioBufferList.allocate(maximumBuffers: 2),output = AudioBufferList.allocate(maximumBuffers: 2)
        defer { input.unsafeMutablePointer.deallocate(); output.unsafeMutablePointer.deallocate() }
        var l = [Float](repeating: 0.2,count: 16),r = [Float](repeating: -0.4,count: 16),ol = [Float](repeating: 9,count: 16),or = ol
        l.withUnsafeMutableBytes { a in r.withUnsafeMutableBytes { b in ol.withUnsafeMutableBytes { c in or.withUnsafeMutableBytes { e in
            input[0] = AudioBuffer(mNumberChannels: 1,mDataByteSize: UInt32(a.count),mData: a.baseAddress); input[1] = AudioBuffer(mNumberChannels: 1,mDataByteSize: UInt32(b.count),mData: b.baseAddress)
            output[0] = AudioBuffer(mNumberChannels: 1,mDataByteSize: UInt32(c.count),mData: c.baseAddress); output[1] = AudioBuffer(mNumberChannels: 1,mDataByteSize: UInt32(e.count),mData: e.baseAddress)
            eq_set_tap_buffers(d,2); var ts = AudioTimeStamp(); _ = eq_io_proc()(0,&ts,input.unsafePointer,&ts,output.unsafeMutablePointer,&ts,UnsafeMutableRawPointer(d))
        } } } }
        XCTAssertEqual(ol[0],0.2,accuracy: 0.00001); XCTAssertEqual(or[0],-0.4,accuracy: 0.00001)
    }
}

final class SettingsTests: XCTestCase {
    func testLocalizationResourcesAndEnglishFallback() {
        XCTAssertEqual(AppLanguage.translate("Enable audio",language: "en"),"Enable audio")
        XCTAssertEqual(AppLanguage.translate("Enable audio",language: "it"),"Attiva audio")
        XCTAssertEqual(AppLanguage.translate("Enable audio",language: "de"),"Audio aktivieren")
        XCTAssertEqual(AppLanguage.translate("Enable audio",language: "fr"),"Activer l’audio")
        XCTAssertEqual(AppLanguage.translate("Enable audio",language: "es"),"Activar audio")
        XCTAssertEqual(AppLanguage.translate("unknown-key",language: "en"),"unknown-key")
    }
    func testAutoEQImport() throws {
        let s = try AutoEQImporter.parse("Preamp: -6.4 dB\nFilter 1: ON PK Fc 1000 Hz Gain -3.2 dB Q 1.41\nFilter 2: ON LSC Fc 105 Hz Gain 5.5 dB Q 0.71\nFilter 3: OFF PK Fc 500 Hz Gain 3 dB Q 1")
        XCTAssertEqual(s.bands.count,2); XCTAssertEqual(s.preamp,-6.4); XCTAssertEqual(s.bands[1].type,.lowShelf)
    }
    func testAutoEQRejectsMalformedEnabledFilter() {
        XCTAssertThrowsError(try AutoEQImporter.parse("Filter 1: ON PK Fc 1000 Hz Gain 3 dB"))
        XCTAssertThrowsError(try AutoEQImporter.parse("Filter 1: ON MAGIC Fc 1000 Hz Gain 3 dB Q 1"))
        XCTAssertThrowsError(try AutoEQImporter.parse("Filter 1: ON PK Fc -1 Hz Gain 3 dB Q 1"))
    }
    func testPresetRoundTrip() throws {
        var settings = AudioSettings(); settings.outputUID = "HDMI-Display"; settings.volume = 0.37; settings.muted = true; settings.appVolumes = ["com.example.player": 0.4]
        let p = Preset(name: "HDMI",settings: settings,deviceUID: "HDMI-Display")
        let decoded = try JSONDecoder().decode(Preset.self,from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded.settings,settings); XCTAssertEqual(decoded.deviceUID,"HDMI-Display")
    }
    func testSettingsRejectNonFiniteAndInvalidVolume() {
        var s = AudioSettings(); s.volume = .nan; XCTAssertThrowsError(try s.validate())
        s.volume = 1.1; XCTAssertThrowsError(try s.validate())
        s.volume = 0.5; s.bands = (0..<65).map { _ in EQBand() }; XCTAssertThrowsError(try s.validate())
    }
    func testVolumeMapping() {
        var s = AudioSettings(); s.volume = 0.5; XCTAssertEqual(s.linearGain,0.25)
        s.muted = true; s.boost = 12; XCTAssertEqual(s.linearGain,0)
    }
}
