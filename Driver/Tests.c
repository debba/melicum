#include "SystemVolume.c"
#include <assert.h>
#include <stdio.h>
#include <unistd.h>

static OSStatus changes(AudioServerPlugInHostRef host,AudioObjectID object,UInt32 count,const AudioObjectPropertyAddress *a) { return noErr; }
static OSStatus beat(int32_t pid,pid_t client) { CFNumberRef value=CFNumberCreate(kCFAllocatorDefault,kCFNumberSInt32Type,&pid);AudioObjectPropertyAddress a={HDMI_HEARTBEAT,kAudioObjectPropertyScopeGlobal,0};OSStatus s=hdmi_set(gAudioServerPlugInDriverRef,kObjectID_Device,client,&a,0,NULL,sizeof(value),&value);CFRelease(value);return s; }
int main(void) {
    assert(Melicum_Create(kCFAllocatorDefault,kAudioServerPlugInTypeUUID));
    AudioServerPlugInHostInterface host={0};host.PropertiesChanged=changes;gPlugIn_Host=&host;
    AudioObjectPropertyAddress a={kAudioDevicePropertyDeviceIsAlive,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    UInt32 size=0,alive=99;
    assert(hdmi_get(gAudioServerPlugInDriverRef,kObjectID_Device,getpid(),&a,0,NULL,4,&size,&alive)==noErr && alive==0);
    AudioObjectPropertyAddress beatAddress={HDMI_HEARTBEAT,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};int32_t pid=getpid();
    assert(hdmi_has(gAudioServerPlugInDriverRef,kObjectID_Device,pid,&beatAddress));
    assert(beat(pid,pid)==noErr);
    assert(hdmi_get(gAudioServerPlugInDriverRef,kObjectID_Device,pid,&a,0,NULL,4,&size,&alive)==noErr && alive==1);
    int32_t wrong=pid+1;assert(beat(wrong,pid)==kAudioHardwareIllegalOperationError);
    AudioObjectPropertyAddress volume={kAudioLevelControlPropertyScalarValue,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};float level=0.5,read=0;
    assert(BlackHole_SetPropertyData(gAudioServerPlugInDriverRef,kObjectID_Volume_Output_Master,pid,&volume,0,NULL,4,&level)==noErr);
    assert(BlackHole_GetPropertyData(gAudioServerPlugInDriverRef,kObjectID_Volume_Output_Master,pid,&volume,0,NULL,4,&size,&read)==noErr);
    assert(fabsf(read-0.5f)<0.0001f);
    pid=0;assert(beat(pid,getpid())==noErr);
    assert(hdmi_get(gAudioServerPlugInDriverRef,kObjectID_Device,getpid(),&a,0,NULL,4,&size,&alive)==noErr && alive==0);
    puts("Driver: initial state, heartbeat, owner validation, volume round trip and shutdown passed.");
}
