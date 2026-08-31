// Hand-written entry point for ffigen. libraw.h itself mixes a C++
// convenience class with LibRaw's plain C API in one file, and the
// installed ffigen version (20.1.1) only parses C, not C++ — so instead of
// pulling in libraw.h (which would fail to parse) this includes the
// pure-C struct/enum definitions from libraw_types.h directly and declares
// just the extern "C" functions we actually call, with signatures copied
// verbatim from libraw.h (verified against the upstream header on
// 2026-08-16, matching third_party/libraw_headers/libraw/libraw.h).
#ifndef DARKMOON_LIBRAW_C_API_H
#define DARKMOON_LIBRAW_C_API_H

#include "libraw/libraw_types.h"

#ifdef __cplusplus
extern "C" {
#endif

DllDef libraw_data_t *libraw_init(unsigned int flags);
DllDef int libraw_open_wfile(libraw_data_t *, const wchar_t *);
// Narrow-string open, used on Linux (libraw_open_wfile isn't even exported
// there — LibRaw only builds the wide-char entry point for WIN32).
DllDef int libraw_open_file(libraw_data_t *, const char *);
DllDef int libraw_unpack(libraw_data_t *);
DllDef int libraw_unpack_thumb(libraw_data_t *);
DllDef int libraw_dcraw_process(libraw_data_t *lr);
DllDef libraw_processed_image_t *libraw_dcraw_make_mem_image(libraw_data_t *lr, int *errc);
DllDef libraw_processed_image_t *libraw_dcraw_make_mem_thumb(libraw_data_t *lr, int *errc);
DllDef void libraw_dcraw_clear_mem(libraw_processed_image_t *);
DllDef void libraw_recycle(libraw_data_t *);
DllDef void libraw_close(libraw_data_t *);
DllDef const char *libraw_strerror(int errorcode);

#ifdef __cplusplus
}
#endif

#endif // DARKMOON_LIBRAW_C_API_H
