// Hand-written entry point for ffigen. dml_provider_factory.h itself
// unconditionally #includes <d3d12.h> (a large COM header, irrelevant to
// the one function we actually call) before declaring
// OrtSessionOptionsAppendExecutionProvider_DML — so instead of using that
// header as ffigen input, this declares just that one function, with its
// signature copied verbatim (verified against the upstream header on
// 2026-08-18, matching third_party/onnxruntime_headers/dml_provider_factory.h,
// ONNX Runtime v1.19.2).
#ifndef DARKMOON_ONNX_DML_C_API_H
#define DARKMOON_ONNX_DML_C_API_H

#include "onnxruntime_c_api.h"

#ifdef __cplusplus
extern "C" {
#endif

// Deprecated in upstream ONNX Runtime in favor of OrtDmlApi's
// SessionOptionsAppendExecutionProvider_DML (reached via the OrtApi function
// table at runtime, not this export) — still the simplest stable entry
// point for registering the DirectML execution provider by plain adapter
// index, which is all this app needs.
ORT_API_STATUS(OrtSessionOptionsAppendExecutionProvider_DML, _In_ OrtSessionOptions* options, int device_id);

#ifdef __cplusplus
}
#endif

#endif // DARKMOON_ONNX_DML_C_API_H
