#pragma once
#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>

#define EQ_MAX_BANDS 64
#define EQ_SPECTRUM_BINS 64
typedef struct EQDSP EQDSP;
EQDSP *eq_create(double sampleRate);
void eq_destroy(EQDSP *dsp);
void eq_set_band(EQDSP *dsp, int index, int type, double hz, double gain, double q, int enabled);
void eq_set_band_count(EQDSP *dsp, int count);
void eq_set_controls(EQDSP *dsp, double gain, double pan, int bypass, int limiter, double wet, double room, double width);
void eq_set_tap_buffers(EQDSP *dsp, int count);
float eq_peak(EQDSP *dsp, int channel);
float eq_spectrum(EQDSP *dsp, int bin);
uint64_t eq_frames(EQDSP *dsp);
int eq_render_error(EQDSP *dsp);
void eq_process(EQDSP *dsp, float *left, float *right, uint32_t frames);
OSStatus eq_add_effect(EQDSP *dsp, AudioUnit unit);
AudioDeviceIOProc eq_io_proc(void);
double eq_response(int type, double hz, double gain, double q, double rate, double frequency);
