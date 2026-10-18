/* System-volume bridge. GPL-3.0.
 * Includes BlackHole source at the pinned commit recorded in UPSTREAM.md.
 * The loopback input is disabled: audio is forwarded by process taps in the app.
 * A heartbeat makes the virtual output unavailable when its owner exits.
 */
// The driver name forms the device UID, which installed builds depend on.
#define kDriver_Name "HDMIAudioSystem"
#define kHas_Driver_Name_Format false
#define kDevice_Name "Melicum"
#define kPlugIn_BundleID "local.melicum.systemvolume"
#define kPlugIn_Icon "AppIcon.icns"
#define kManufacturer_Name "Melicum"
#define kNumber_Of_Channels 2
#define kDevice_HasInput false
#define kDevice_HasOutput true
#define kDevice2_HasInput false
#define kDevice2_HasOutput false
#define kDevice2_IsHidden true
#define kSampleRates 44100,48000,88200,96000,176400,192000
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-extra-args"
#include "../ThirdParty/BlackHole/BlackHole/BlackHole.c"
#pragma clang diagnostic pop
#include <stdatomic.h>
#include <signal.h>
#include <errno.h>

#define HDMI_HEARTBEAT ((AudioObjectPropertySelector)0x68616374)
static _Atomic bool hdmiAlive = false;
static _Atomic uint64_t hdmiLastBeat = 0;
static _Atomic int32_t hdmiOwner = 0;
static dispatch_source_t hdmiWatchdog;
static const AudioServerPlugInCustomPropertyInfo hdmiProperties[] = {
    { HDMI_HEARTBEAT,kAudioServerPlugInCustomPropertyDataTypeCFPropertyList,kAudioServerPlugInCustomPropertyDataTypeNone }
};

static void hdmi_set_alive(bool alive) {
    if (atomic_exchange(&hdmiAlive,alive) != alive && gPlugIn_Host) {
        AudioObjectPropertyAddress a = { kAudioDevicePropertyDeviceIsAlive,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain };
        gPlugIn_Host->PropertiesChanged(gPlugIn_Host,kObjectID_Device,1,&a);
    }
}
static bool hdmi_custom(AudioObjectID object,const AudioObjectPropertyAddress *a) {
    return object == kObjectID_Device && a && a->mSelector == HDMI_HEARTBEAT;
}
static OSStatus hdmi_initialize(AudioServerPlugInDriverRef driver,AudioServerPlugInHostRef host) {
    OSStatus s = BlackHole_Initialize(driver,host);
    if(s || hdmiWatchdog) return s;
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    const double secondsPerTick = (double)tb.numer/tb.denom/1e9;
    hdmiWatchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_global_queue(QOS_CLASS_UTILITY,0));
    dispatch_source_set_timer(hdmiWatchdog,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC,NSEC_PER_SEC/10);
    dispatch_source_set_event_handler(hdmiWatchdog,^{
        int32_t pid = atomic_load(&hdmiOwner);
        int result = pid>0 ? kill(pid,0) : 0;
        bool ownerGone = result<0 && errno==ESRCH;
        if (atomic_load(&hdmiAlive) && (pid <= 0 || (mach_absolute_time()-atomic_load(&hdmiLastBeat))*secondsPerTick > 5 || ownerGone)) hdmi_set_alive(false);
    });
    dispatch_resume(hdmiWatchdog);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/4),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        AudioObjectPropertyAddress a={kAudioDevicePropertyDeviceIsAlive,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
        gPlugIn_Host->PropertiesChanged(gPlugIn_Host,kObjectID_Device,1,&a);
    });
    return noErr;
}
static Boolean hdmi_has(AudioServerPlugInDriverRef driver,AudioObjectID object,pid_t client,const AudioObjectPropertyAddress *a) {
    return hdmi_custom(object,a) || (object==kObjectID_Device && a && a->mSelector==kAudioObjectPropertyCustomPropertyInfoList) || BlackHole_HasProperty(driver,object,client,a);
}
static OSStatus hdmi_settable(AudioServerPlugInDriverRef driver,AudioObjectID object,pid_t client,const AudioObjectPropertyAddress *a,Boolean *out) {
    if(hdmi_custom(object,a)) { if(!out)return kAudioHardwareIllegalOperationError; *out=true;return noErr; }
    return BlackHole_IsPropertySettable(driver,object,client,a,out);
}
static OSStatus hdmi_size(AudioServerPlugInDriverRef driver,AudioObjectID object,pid_t client,const AudioObjectPropertyAddress *a,UInt32 qsize,const void *q,UInt32 *size) {
    if(object==kObjectID_Device && a && a->mSelector==kAudioObjectPropertyCustomPropertyInfoList) { if(!size)return kAudioHardwareIllegalOperationError;*size=sizeof(hdmiProperties);return noErr; }
    if(hdmi_custom(object,a)) { if(!size)return kAudioHardwareIllegalOperationError;*size=sizeof(CFPropertyListRef);return noErr; }
    return BlackHole_GetPropertyDataSize(driver,object,client,a,qsize,q,size);
}
static OSStatus hdmi_get(AudioServerPlugInDriverRef driver,AudioObjectID object,pid_t client,const AudioObjectPropertyAddress *a,UInt32 qsize,const void *q,UInt32 capacity,UInt32 *size,void *data) {
    if(object==kObjectID_Device && a && a->mSelector==kAudioObjectPropertyCustomPropertyInfoList) {
        if(capacity<sizeof(hdmiProperties) || !size || !data)return kAudioHardwareBadPropertySizeError;
        memcpy(data,hdmiProperties,sizeof(hdmiProperties));*size=sizeof(hdmiProperties);return noErr;
    }
    if(hdmi_custom(object,a)) {
        if(capacity<sizeof(CFNumberRef) || !size || !data)return kAudioHardwareBadPropertySizeError;
        int32_t owner=atomic_load(&hdmiOwner);*(CFNumberRef*)data=CFNumberCreate(kCFAllocatorDefault,kCFNumberSInt32Type,&owner);*size=sizeof(CFNumberRef);return noErr;
    }
    if(object==kObjectID_Device && a && a->mSelector==kAudioDevicePropertyDeviceIsAlive) {
        if(capacity<4 || !size || !data)return kAudioHardwareBadPropertySizeError;
        *size=4;*(UInt32*)data=atomic_load(&hdmiAlive);return noErr;
    }
    return BlackHole_GetPropertyData(driver,object,client,a,qsize,q,capacity,size,data);
}
static OSStatus hdmi_set(AudioServerPlugInDriverRef driver,AudioObjectID object,pid_t client,const AudioObjectPropertyAddress *a,UInt32 qsize,const void *q,UInt32 size,const void *data) {
    if(hdmi_custom(object,a)) {
        if(size!=sizeof(CFNumberRef) || !data)return kAudioHardwareBadPropertySizeError;
        CFNumberRef number=*(CFNumberRef*)data;int32_t pid=0;
        if(!number || CFGetTypeID(number)!=CFNumberGetTypeID() || !CFNumberGetValue(number,kCFNumberSInt32Type,&pid) || pid<0)return kAudioHardwareIllegalOperationError;
        if(pid!=0 && client>0 && pid!=client)return kAudioHardwareIllegalOperationError;
        atomic_store(&hdmiOwner,pid);atomic_store(&hdmiLastBeat,mach_absolute_time());hdmi_set_alive(pid>0);return noErr;
    }
    return BlackHole_SetPropertyData(driver,object,client,a,qsize,q,size,data);
}

__attribute__((visibility("default"))) void *Melicum_Create(CFAllocatorRef allocator,CFUUIDRef type) {
    void *driver=BlackHole_Create(allocator,type);
    if(driver) {
        gAudioServerPlugInDriverInterface.Initialize=hdmi_initialize;
        gAudioServerPlugInDriverInterface.HasProperty=hdmi_has;
        gAudioServerPlugInDriverInterface.IsPropertySettable=hdmi_settable;
        gAudioServerPlugInDriverInterface.GetPropertyDataSize=hdmi_size;
        gAudioServerPlugInDriverInterface.GetPropertyData=hdmi_get;
        gAudioServerPlugInDriverInterface.SetPropertyData=hdmi_set;
    }
    return driver;
}
