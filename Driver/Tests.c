#include "SystemVolume.c"
#include <assert.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/wait.h>

static unsigned aliveChanges,hiddenChanges,nameChanges;
static OSStatus changes(AudioServerPlugInHostRef host,AudioObjectID object,UInt32 count,const AudioObjectPropertyAddress *addresses) {
    if(object!=kObjectID_Device)return noErr;
    for(UInt32 i=0;i<count;i++) {
        if(addresses[i].mSelector==kAudioDevicePropertyDeviceIsAlive)aliveChanges++;
        if(addresses[i].mSelector==kAudioDevicePropertyIsHidden)hiddenChanges++;
        if(addresses[i].mSelector==kAudioObjectPropertyName)nameChanges++;
    }
    return noErr;
}
static OSStatus beat(int32_t pid,pid_t client) {
    CFNumberRef value=CFNumberCreate(kCFAllocatorDefault,kCFNumberSInt32Type,&pid);
    AudioObjectPropertyAddress address={HDMI_HEARTBEAT,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    OSStatus status=hdmi_set(gAudioServerPlugInDriverRef,kObjectID_Device,client,&address,0,NULL,sizeof(value),&value);
    CFRelease(value);return status;
}
static void expect_state(bool active) {
    const AudioObjectPropertySelector selectors[]={kAudioDevicePropertyDeviceIsAlive,kAudioDevicePropertyIsHidden};
    for(unsigned i=0;i<2;i++) {
        AudioObjectPropertyAddress address={selectors[i],kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
        UInt32 size=0,value=99;
        assert(hdmi_has(gAudioServerPlugInDriverRef,kObjectID_Device,getpid(),&address));
        assert(hdmi_size(gAudioServerPlugInDriverRef,kObjectID_Device,getpid(),&address,0,NULL,&size)==noErr && size==sizeof(value));
        assert(hdmi_get(gAudioServerPlugInDriverRef,kObjectID_Device,getpid(),&address,0,NULL,sizeof(value),&size,&value)==noErr);
        assert(value==(i==0 ? active : !active));
        assert(hdmi_get(gAudioServerPlugInDriverRef,kObjectID_Device,getpid(),&address,0,NULL,0,&size,&value)==kAudioHardwareBadPropertySizeError);
    }
    assert(aliveChanges==hiddenChanges);
}
static void expect_name(CFStringRef expected) {
    AudioObjectPropertyAddress address={kAudioObjectPropertyName,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    UInt32 size=0;CFStringRef name=NULL;
    assert(hdmi_size(gAudioServerPlugInDriverRef,kObjectID_Device,getpid(),&address,0,NULL,&size)==noErr && size==sizeof(name));
    assert(hdmi_get(gAudioServerPlugInDriverRef,kObjectID_Device,getpid(),&address,0,NULL,sizeof(name),&size,&name)==noErr);
    assert(CFEqual(name,expected));CFRelease(name);
    address.mSelector=MELICUM_DEVICE_NAME;
    assert(hdmi_get(gAudioServerPlugInDriverRef,kObjectID_Device,getpid(),&address,0,NULL,sizeof(name),&size,&name)==noErr);
    assert(CFEqual(name,expected));CFRelease(name);
    address.mSelector=kAudioDevicePropertyDeviceUID;
    assert(hdmi_get(gAudioServerPlugInDriverRef,kObjectID_Device,getpid(),&address,0,NULL,sizeof(name),&size,&name)==noErr);
    assert(CFEqual(name,CFSTR("HDMIAudioSystem_UID")));CFRelease(name);
}
static OSStatus rename_device(CFStringRef name) {
    AudioObjectPropertyAddress address={MELICUM_DEVICE_NAME,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    return hdmi_set(gAudioServerPlugInDriverRef,kObjectID_Device,getpid(),&address,0,NULL,sizeof(name),&name);
}
int main(void) {
    assert(Melicum_Create(kCFAllocatorDefault,kAudioServerPlugInTypeUUID));
    AudioServerPlugInHostInterface host={0};host.PropertiesChanged=changes;gPlugIn_Host=&host;
    expect_state(false);
    expect_name(CFSTR("Melicum"));
    AudioObjectPropertyAddress nameAddress={MELICUM_DEVICE_NAME,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    Boolean settable=false;
    assert(hdmi_has(gAudioServerPlugInDriverRef,kObjectID_Device,getpid(),&nameAddress));
    assert(hdmi_settable(gAudioServerPlugInDriverRef,kObjectID_Device,getpid(),&nameAddress,&settable)==noErr && settable);
    AudioObjectPropertyAddress standardName={kAudioObjectPropertyName,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    assert(hdmi_settable(gAudioServerPlugInDriverRef,kObjectID_Device,getpid(),&standardName,&settable)==noErr && !settable);
    assert(rename_device(CFSTR("DELL U2414H (Melicum)"))==noErr);expect_name(CFSTR("DELL U2414H (Melicum)"));assert(nameChanges==1);
    assert(rename_device(CFSTR("DELL U2414H (Melicum)"))==noErr);assert(nameChanges==1);
    CFMutableStringRef mutableName=CFStringCreateMutableCopy(kCFAllocatorDefault,0,CFSTR("Studio 🎧 USB-C (Melicum)"));
    assert(rename_device(mutableName)==noErr);
    CFStringAppend(mutableName,CFSTR(" changed"));CFRelease(mutableName);
    expect_name(CFSTR("Studio 🎧 USB-C (Melicum)"));assert(nameChanges==2);
    assert(rename_device(CFSTR(""))==kAudioHardwareIllegalOperationError);
    assert(rename_device(NULL)==kAudioHardwareIllegalOperationError);
    int invalidValue=7;CFNumberRef invalidName=CFNumberCreate(kCFAllocatorDefault,kCFNumberIntType,&invalidValue);
    assert(hdmi_set(gAudioServerPlugInDriverRef,kObjectID_Device,getpid(),&nameAddress,0,NULL,sizeof(invalidName),&invalidName)==kAudioHardwareIllegalOperationError);
    CFRelease(invalidName);
    assert(hdmi_set(gAudioServerPlugInDriverRef,kObjectID_Device,getpid(),&nameAddress,0,NULL,0,NULL)==kAudioHardwareBadPropertySizeError);
    expect_name(CFSTR("Studio 🎧 USB-C (Melicum)"));assert(nameChanges==2);
    AudioObjectPropertyAddress beatAddress={HDMI_HEARTBEAT,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};int32_t pid=getpid();
    assert(hdmi_has(gAudioServerPlugInDriverRef,kObjectID_Device,pid,&beatAddress));
    assert(beat(pid,pid)==noErr);expect_state(true);assert(aliveChanges==1);
    assert(beat(pid,pid)==noErr);assert(aliveChanges==1);
    assert(beat(pid+1,pid)==kAudioHardwareIllegalOperationError);expect_state(true);
    AudioObjectPropertyAddress volume={kAudioLevelControlPropertyScalarValue,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};float level=0.5,read=0;UInt32 size=0;
    assert(BlackHole_SetPropertyData(gAudioServerPlugInDriverRef,kObjectID_Volume_Output_Master,pid,&volume,0,NULL,4,&level)==noErr);
    assert(BlackHole_GetPropertyData(gAudioServerPlugInDriverRef,kObjectID_Volume_Output_Master,pid,&volume,0,NULL,4,&size,&read)==noErr);
    assert(fabsf(read-0.5f)<0.0001f);
    assert(beat(0,pid)==noErr);expect_state(false);assert(aliveChanges==2);

    mach_timebase_info_data_t timebase;mach_timebase_info(&timebase);
    double secondsPerTick=(double)timebase.numer/timebase.denom/1e9;
    assert(beat(pid,pid)==noErr);
    uint64_t lastBeat=atomic_load(&hdmiLastBeat);
    hdmi_check_owner(lastBeat-1,secondsPerTick);expect_state(true);
    hdmi_check_owner(lastBeat+(uint64_t)(4/secondsPerTick),secondsPerTick);expect_state(true);
    hdmi_check_owner(lastBeat+(uint64_t)(6/secondsPerTick),secondsPerTick);expect_state(false);
    assert(beat(pid,pid)==noErr);expect_state(true);
    assert(beat(0,pid)==noErr);expect_state(false);

    pid_t child=fork();assert(child>=0);
    if(child==0)_exit(0);
    assert(waitpid(child,NULL,0)==child);
    assert(beat(child,child)==noErr);expect_state(true);
    hdmi_check_owner(mach_absolute_time(),secondsPerTick);expect_state(false);
    puts("Driver: output names, stable UID, property validation, hidden startup, notifications, heartbeat, owner validation, volume, shutdown, timeout and owner exit passed.");
}
