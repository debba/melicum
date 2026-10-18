#include "AudioDSP.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define MAX_FRAMES 8192
#define FFT_N 2048
#define REVERB_N 16384
#define MAX_EFFECTS 12
typedef struct {
    _Atomic double hz, gain, q;
    _Atomic int type, enabled;
    double b0,b1,b2,a1,a2,z1[2],z2[2];
    double oldHz,oldGain,oldQ;
    int oldType, oldEnabled;
} Band;
struct EQDSP {
    double rate;
    Band bands[EQ_MAX_BANDS];
    _Atomic int count, bypass, limiter;
    _Atomic double gain, pan, wet, room, width;
    _Atomic float peak[2], spectrum[EQ_SPECTRUM_BINS];
    _Atomic uint64_t frames;
    _Atomic int renderError;
    double smoothGain, smoothPan;
    int tapBuffers;
    float *scratch[4];
    float history[FFT_N], fftReal[FFT_N], fftImag[FFT_N];
    int historyIndex;
    float *reverb[2][4];
    int reverbIndex[2][4];
    AudioUnit effects[MAX_EFFECTS];
    int effectCount;
    float *effectLeft, *effectRight;
    uint32_t effectFrames;
    double sampleTime;
};
static double bounded(double v, double lo, double hi) { return fmax(lo,fmin(hi,isfinite(v)?v:lo)); }
EQDSP *eq_create(double sampleRate) {
    if (!isfinite(sampleRate) || sampleRate < 8000 || sampleRate > 384000) return NULL;
    EQDSP *d=calloc(1,sizeof(EQDSP));
    if(!d) return NULL;
    d->rate=sampleRate; d->tapBuffers=1;
    atomic_store(&d->gain,0.25); atomic_store(&d->limiter,1); atomic_store(&d->width,1);
    for(int i=0;i<EQ_SPECTRUM_BINS;i++)atomic_store(&d->spectrum[i],-100);
    for(int i=0;i<EQ_MAX_BANDS;i++) {d->bands[i].oldHz=-1; atomic_store(&d->bands[i].hz,1000); atomic_store(&d->bands[i].q,0.707);}
    for(int i=0;i<4;i++) {d->scratch[i]=calloc(MAX_FRAMES,sizeof(float)); if(!d->scratch[i]) {eq_destroy(d);return NULL;}}
    for(int c=0;c<2;c++) for(int i=0;i<4;i++) { d->reverb[c][i]=calloc(REVERB_N,sizeof(float)); if(!d->reverb[c][i]) {eq_destroy(d);return NULL;} }
    return d;
}
void eq_destroy(EQDSP *d) { if(!d)return; for(int i=0;i<4;i++)free(d->scratch[i]);for(int c=0;c<2;c++)for(int i=0;i<4;i++)free(d->reverb[c][i]);free(d); }
void eq_set_band(EQDSP *d,int i,int t,double h,double g,double q,int en) {
    if(!d||i<0||i>=EQ_MAX_BANDS)return;
    Band *b=&d->bands[i];atomic_store(&b->hz,bounded(h,10,d->rate*0.49));atomic_store(&b->gain,bounded(g,-30,30));atomic_store(&b->q,bounded(q,0.1,20));atomic_store(&b->type,t);atomic_store(&b->enabled,en);
}
void eq_set_band_count(EQDSP *d,int n) {if(d) atomic_store(&d->count,n<0?0:(n>EQ_MAX_BANDS?EQ_MAX_BANDS:n));}
void eq_set_controls(EQDSP *d,double g,double p,int b,int l,double w,double r,double width) {
    if(!d)return;atomic_store(&d->gain,bounded(g,0,16));atomic_store(&d->pan,bounded(p,-1,1));atomic_store(&d->bypass,b);atomic_store(&d->limiter,l);atomic_store(&d->wet,bounded(w,0,1));atomic_store(&d->room,bounded(r,0,4));atomic_store(&d->width,bounded(width,0,2));
}
void eq_set_tap_buffers(EQDSP *d,int n){if(d)d->tapBuffers=n>0?n:1;}
float eq_peak(EQDSP *d,int c){return d&&c>=0&&c<2?atomic_load(&d->peak[c]):0;}
float eq_spectrum(EQDSP *d,int b){return d&&b>=0&&b<EQ_SPECTRUM_BINS?atomic_load(&d->spectrum[b]):-100;}
uint64_t eq_frames(EQDSP *d){return d?atomic_load(&d->frames):0;}
int eq_render_error(EQDSP *d){return d?atomic_load(&d->renderError):0;}
static void coefficients(Band *b,double rate) {
    double h=atomic_load(&b->hz),g=atomic_load(&b->gain),q=atomic_load(&b->q);int t=atomic_load(&b->type),en=atomic_load(&b->enabled);
    if(h==b->oldHz&&g==b->oldGain&&q==b->oldQ&&t==b->oldType&&en==b->oldEnabled)return;
    b->oldHz=h;b->oldGain=g;b->oldQ=q;b->oldType=t;b->oldEnabled=en;
    double w=2*M_PI*h/rate,c=cos(w),s=sin(w),A=pow(10,g/40),a=s/(2*q),v=2*sqrt(A)*a;
    double b0=1,b1=0,b2=0,a0=1,a1=0,a2=0;
    if(en) switch(t) {
      case 0: b0=1+a*A;b1=-2*c;b2=1-a*A;a0=1+a/A;a1=-2*c;a2=1-a/A;break;
      case 1: b0=A*((A+1)-(A-1)*c+v);b1=2*A*((A-1)-(A+1)*c);b2=A*((A+1)-(A-1)*c-v);a0=(A+1)+(A-1)*c+v;a1=-2*((A-1)+(A+1)*c);a2=(A+1)+(A-1)*c-v;break;
      case 2: b0=A*((A+1)+(A-1)*c+v);b1=-2*A*((A-1)+(A+1)*c);b2=A*((A+1)+(A-1)*c-v);a0=(A+1)-(A-1)*c+v;a1=2*((A-1)-(A+1)*c);a2=(A+1)-(A-1)*c-v;break;
      case 3: b0=(1-c)/2;b1=1-c;b2=b0;a0=1+a;a1=-2*c;a2=1-a;break;
      case 4: b0=(1+c)/2;b1=-(1+c);b2=b0;a0=1+a;a1=-2*c;a2=1-a;break;
      case 5: b0=1;b1=-2*c;b2=1;a0=1+a;a1=-2*c;a2=1-a;break;
      case 6: b0=a;b1=0;b2=-a;a0=1+a;a1=-2*c;a2=1-a;break;
    }
    b->b0=b0/a0;b->b1=b1/a0;b->b2=b2/a0;b->a1=a1/a0;b->a2=a2/a0;
    if(!en)memset(b->z1,0,sizeof(b->z1)),memset(b->z2,0,sizeof(b->z2));
}
static void analyze(EQDSP *d) {
    for(int i=0;i<FFT_N;i++){d->fftReal[i]=d->history[i]*(0.5-0.5*cos(2*M_PI*i/(FFT_N-1)));d->fftImag[i]=0;}
    for(int i=1,j=0;i<FFT_N;i++){int bit=FFT_N>>1;for(;j&bit;bit>>=1)j^=bit;j^=bit;if(i<j){float t=d->fftReal[i];d->fftReal[i]=d->fftReal[j];d->fftReal[j]=t;}}
    for(int len=2;len<=FFT_N;len<<=1){double ang=-2*M_PI/len;for(int i=0;i<FFT_N;i+=len){double wr=1,wi=0;for(int j=0;j<len/2;j++){int u=i+j,v=u+len/2;double vr=d->fftReal[v]*wr-d->fftImag[v]*wi,vi=d->fftReal[v]*wi+d->fftImag[v]*wr;d->fftReal[v]=d->fftReal[u]-vr;d->fftImag[v]=d->fftImag[u]-vi;d->fftReal[u]+=vr;d->fftImag[u]+=vi;double next=wr*cos(ang)-wi*sin(ang);wi=wr*sin(ang)+wi*cos(ang);wr=next;}}}
    for(int b=0;b<EQ_SPECTRUM_BINS;b++){double hz=20*pow(1000,(double)b/(EQ_SPECTRUM_BINS-1));int k=(int)round(hz*FFT_N/d->rate);if(k<1)k=1;if(k>=FFT_N/2)k=FFT_N/2-1;double mag=hypot(d->fftReal[k],d->fftImag[k])*4/FFT_N;float db=20*log10(fmax(mag,1e-5));float old=atomic_load(&d->spectrum[b]);atomic_store(&d->spectrum[b],fmax(db,old-4));}
}
double eq_response(int type,double hz,double gain,double q,double rate,double frequency) {
    Band b={0};b.oldHz=-1;atomic_store(&b.hz,bounded(hz,10,rate*0.49));atomic_store(&b.gain,gain);atomic_store(&b.q,q);atomic_store(&b.type,type);atomic_store(&b.enabled,1);coefficients(&b,rate);
    double w=2*M_PI*frequency/rate,c=cos(w),s=sin(w),c2=cos(2*w),s2=sin(2*w);
    double num=hypot(b.b0+b.b1*c+b.b2*c2,-b.b1*s-b.b2*s2),den=hypot(1+b.a1*c+b.a2*c2,-b.a1*s-b.a2*s2);
    return 20*log10(fmax(num/fmax(den,1e-15),1e-8));
}
static OSStatus effect_input(void *ctx,AudioUnitRenderActionFlags *flags,const AudioTimeStamp *ts,UInt32 bus,UInt32 frames,AudioBufferList *data){
    EQDSP *d=ctx; if(frames>d->effectFrames)return kAudioUnitErr_TooManyFramesToProcess;
    for(UInt32 b=0;b<data->mNumberBuffers;b++){float *source=b==0?d->effectLeft:d->effectRight;if(data->mBuffers[b].mData)memcpy(data->mBuffers[b].mData,source,frames*sizeof(float));else data->mBuffers[b].mData=source;data->mBuffers[b].mDataByteSize=frames*sizeof(float);}return noErr;
}
OSStatus eq_add_effect(EQDSP *d,AudioUnit u){
    if(!d||d->effectCount>=MAX_EFFECTS)return kAudioUnitErr_InvalidParameter;
    AudioStreamBasicDescription fmt={.mSampleRate=d->rate,.mFormatID=kAudioFormatLinearPCM,.mFormatFlags=kAudioFormatFlagsNativeFloatPacked|kAudioFormatFlagIsNonInterleaved,.mBytesPerPacket=4,.mFramesPerPacket=1,.mBytesPerFrame=4,.mChannelsPerFrame=2,.mBitsPerChannel=32};
    UInt32 max=MAX_FRAMES;OSStatus s=AudioUnitSetProperty(u,kAudioUnitProperty_MaximumFramesPerSlice,kAudioUnitScope_Global,0,&max,sizeof(max));if(s)return s;
    s=AudioUnitSetProperty(u,kAudioUnitProperty_StreamFormat,kAudioUnitScope_Input,0,&fmt,sizeof(fmt));if(s)return s;
    s=AudioUnitSetProperty(u,kAudioUnitProperty_StreamFormat,kAudioUnitScope_Output,0,&fmt,sizeof(fmt));if(s)return s;
    AURenderCallbackStruct cb={effect_input,d};s=AudioUnitSetProperty(u,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&cb,sizeof(cb));if(s)return s;
    s=AudioUnitInitialize(u);if(s)return s;d->effects[d->effectCount++]=u;return noErr;
}
void eq_process(EQDSP *d,float *l,float *r,uint32_t n){
    if(!d||!l||!r||n>MAX_FRAMES)return;
    int count=atomic_load(&d->count),bypass=atomic_load(&d->bypass),limiter=atomic_load(&d->limiter);double target=atomic_load(&d->gain),pan=atomic_load(&d->pan),wet=bypass?0:atomic_load(&d->wet),room=atomic_load(&d->room),width=bypass?1:atomic_load(&d->width);
    for(int b=0;b<count;b++)coefficients(&d->bands[b],d->rate);
    const int delays[4]={1557,1617,1491,1422};int lens[2][4];for(int c=0;c<2;c++)for(int b=0;b<4;b++)lens[c][b]=(int)bounded((delays[b]+c*37)*d->rate/44100*(0.7+room*0.28),1,REVERB_N-1);
    for(uint32_t i=0;i<n;i++){
        double v[2]={isfinite(l[i])?l[i]:0,isfinite(r[i])?r[i]:0};
        if(!bypass)for(int b=0;b<count;b++){Band *f=&d->bands[b];if(!atomic_load(&f->enabled))continue;for(int c=0;c<2;c++){double out=f->b0*v[c]+f->z1[c];f->z1[c]=f->b1*v[c]-f->a1*out+f->z2[c];f->z2[c]=f->b2*v[c]-f->a2*out;v[c]=out;}}
        if(wet>0)for(int c=0;c<2;c++){double sum=0;for(int b=0;b<4;b++){int p=d->reverbIndex[c][b]%lens[c][b];float delayed=d->reverb[c][b][p];d->reverb[c][b][p]=v[c]+delayed*(0.6+room*0.055);d->reverbIndex[c][b]=(p+1)%lens[c][b];sum+=delayed;}v[c]=v[c]*(1-wet)+sum*0.25*wet;}
        double mid=(v[0]+v[1])*0.5,side=(v[0]-v[1])*0.5*width;l[i]=mid+side;r[i]=mid-side;
    }
    if(!bypass)for(int e=0;e<d->effectCount;e++){
        d->effectLeft=l;d->effectRight=r;d->effectFrames=n;
        struct{UInt32 count;AudioBuffer buffers[2];} out={2,{{1,n*sizeof(float),d->scratch[2]},{1,n*sizeof(float),d->scratch[3]}}};
        AudioTimeStamp ts={.mSampleTime=d->sampleTime,.mFlags=kAudioTimeStampSampleTimeValid};AudioUnitRenderActionFlags flags=0;OSStatus s=AudioUnitRender(d->effects[e],&flags,&ts,0,n,(AudioBufferList*)&out);
        if(!s){memcpy(l,out.buffers[0].mData,n*sizeof(float));memcpy(r,out.buffers[1].mData,n*sizeof(float));}else atomic_store(&d->renderError,s);
    }
    d->sampleTime+=n;float peak[2]={0,0};double smooth=1-exp(-1/(d->rate*0.008));
    for(uint32_t i=0;i<n;i++){
        d->smoothGain+=(target-d->smoothGain)*smooth;d->smoothPan+=(pan-d->smoothPan)*smooth;
        float vals[2]={l[i]*d->smoothGain*(d->smoothPan>0?1-d->smoothPan:1),r[i]*d->smoothGain*(d->smoothPan<0?1+d->smoothPan:1)};
        for(int c=0;c<2;c++){if(!isfinite(vals[c]))vals[c]=0;if(limiter)vals[c]=fmaxf(-0.98f,fminf(0.98f,vals[c]));peak[c]=fmaxf(peak[c],fabsf(vals[c]));}
        l[i]=vals[0];r[i]=vals[1];d->history[d->historyIndex++]=(vals[0]+vals[1])*0.5;
        if(d->historyIndex==FFT_N){d->historyIndex=0;analyze(d);}
    }
    for(int c=0;c<2;c++)atomic_store(&d->peak[c],fmaxf(peak[c],atomic_load(&d->peak[c])*0.90));
    atomic_fetch_add(&d->frames,n);
}
static OSStatus io(AudioObjectID device,const AudioTimeStamp *now,const AudioBufferList *input,const AudioTimeStamp *it,AudioBufferList *output,const AudioTimeStamp *ot,void *ctx){
    EQDSP *d=ctx;for(UInt32 b=0;b<output->mNumberBuffers;b++)if(output->mBuffers[b].mData)memset(output->mBuffers[b].mData,0,output->mBuffers[b].mDataByteSize);
    if(!input||input->mNumberBuffers==0||output->mNumberBuffers==0)return noErr;
    int start=(int)input->mNumberBuffers-d->tapBuffers;if(start<0)start=0;
    const AudioBuffer *first=&input->mBuffers[start];if(!first->mData||!first->mNumberChannels)return noErr;
    UInt32 n=first->mDataByteSize/(sizeof(float)*first->mNumberChannels);if(n>MAX_FRAMES)return noErr;
    float *l=d->scratch[0],*r=d->scratch[1];
    if(first->mNumberChannels>=2){float *p=first->mData;for(UInt32 i=0;i<n;i++){l[i]=p[i*first->mNumberChannels];r[i]=p[i*first->mNumberChannels+1];}}
    else{memcpy(l,first->mData,n*sizeof(float));const AudioBuffer *second=start+1<input->mNumberBuffers?&input->mBuffers[start+1]:first;if(!second->mData||second->mDataByteSize<n*sizeof(float))return noErr;memcpy(r,second->mData,n*sizeof(float));}
    eq_process(d,l,r,n);
    int channel=0;for(UInt32 b=0;b<output->mNumberBuffers&&channel<2;b++){AudioBuffer *out=&output->mBuffers[b];if(!out->mData||!out->mNumberChannels)continue;UInt32 cap=out->mDataByteSize/(sizeof(float)*out->mNumberChannels),frames=cap<n?cap:n;float *p=out->mData;for(UInt32 c=0;c<out->mNumberChannels&&channel<2;c++,channel++)for(UInt32 i=0;i<frames;i++)p[i*out->mNumberChannels+c]=channel==0?l[i]:r[i];}
    return noErr;
}
AudioDeviceIOProc eq_io_proc(void){return io;}
