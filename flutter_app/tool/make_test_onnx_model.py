#!/usr/bin/env python3
"""Emits a tiny ONNX model shaped like darkmoon's denoise model.

Exists so CI can prove the *whole* ONNX stack works on a platform — not
just that libonnxruntime loads, but that a session is created, an
execution provider is chosen, and inference runs and returns sane values.
The real weights are gitignored (~1.2GB), so without this CI can only ever
check that the library opened.

Matches OnnxModelSpec.customDenoiseModel's contract: 3-channel RGB,
same-resolution in and out, tensors named "input" and "output". The graph
is a single Mul by 1.0 — an identity in everything but name, chosen over a
literal Identity node so there is a real operator for an execution
provider to place on the GPU.

Usage: python3 tool/make_test_onnx_model.py <output.onnx>
"""
import sys

import numpy as np
import onnx
from onnx import TensorProto, helper, numpy_helper

out_path = sys.argv[1] if len(sys.argv) > 1 else "identity_test_model.onnx"

# Dynamic spatial dims, like the real models — the tile size is the
# caller's choice, not the graph's.
inp = helper.make_tensor_value_info(
    "input", TensorProto.FLOAT, [1, 3, "h", "w"])
out = helper.make_tensor_value_info(
    "output", TensorProto.FLOAT, [1, 3, "h", "w"])

one = numpy_helper.from_array(np.array([1.0], dtype=np.float32), name="one")
node = helper.make_node("Mul", ["input", "one"], ["output"])

graph = helper.make_graph([node], "darkmoon_smoke", [inp], [out], [one])
model = helper.make_model(
    graph, opset_imports=[helper.make_opsetid("", 17)])
model.ir_version = 9
onnx.checker.check_model(model)
onnx.save(model, out_path)
print(f"wrote {out_path}")
